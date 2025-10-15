import json
import os
import sys
from base64 import b64decode
from os import path as osp
from subprocess import check_call, run
from textwrap import dedent

import pytest
from pytest_infrahouse import terraform_apply

from tests.conftest import (
    LOG,
    TERRAFORM_ROOT_DIR,
)


@pytest.mark.parametrize(
    "aws_provider_version", ["~> 5.11", "~> 6.0"], ids=["aws5", "aws6"]
)
def test_module(
    service_network,
    aws_region,
    test_role_arn,
    test_zone_name,
    keep_after,
    boto3_session,
    aws_provider_version,
    cleanup_ecs_task_definitions,
):
    subnet_public_ids = service_network["subnet_public_ids"]["value"]

    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "openvpn")

    # Clean up any existing Terraform state and lock files
    check_call(
        ["rm", "-rf", ".terraform", ".terraform.lock.hcl"], cwd=terraform_module_dir
    )

    # Update terraform.tf with the specified AWS provider version
    terraform_tf_content = dedent(
        f"""
        terraform {{
          required_providers {{
            aws = {{
              source  = "hashicorp/aws"
              version = "{aws_provider_version}"
            }}
          }}
        }}
        """
    )

    with open(osp.join(terraform_module_dir, "terraform.tf"), "w") as fp:
        fp.write(terraform_tf_content)

    with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
        fp.write(
            dedent(
                f"""
                region             = "{aws_region}"
                test_zone          = "{test_zone_name}"

                lb_subnet_ids      = {json.dumps(subnet_public_ids)}
                backend_subnet_ids = {json.dumps(subnet_public_ids)}
                """
            )
        )
        if test_role_arn:
            fp.write(
                dedent(
                    f"""
                    role_arn        = "{test_role_arn}"
                    """
                )
            )

    LOG.info("Testing with AWS provider version: %s", aws_provider_version)

    with terraform_apply(
        terraform_module_dir,
        destroy_after=not keep_after,
    ) as tf_output:
        LOG.info("%s", json.dumps(tf_output, indent=4))
        # update Google OAuth 2.0 Client IDs
        google_client_secret = tf_output["google_client_secret"]["value"]
        try:
            # Try to read client_secret from environment variable first
            client_secret = os.environ.get("OPENVPN_CLIENT_SECRET")
            if not client_secret:
                # Fall back to reading from file
                client_secret_path = osp.join(
                    terraform_module_dir, "env", "client_secret.json"
                )
                client_secret = open(client_secret_path).read()

            secretsmanager_client = boto3_session.client(
                "secretsmanager", region_name=aws_region
            )
            secretsmanager_client.put_secret_value(
                SecretId=google_client_secret, SecretString=client_secret
            )
        except FileNotFoundError as err:
            LOG.error("%s", err)
            LOG.error(
                "Get OAuth 2.0 Client IDs from https://console.cloud.google.com/auth/clients and put it in %s",
                client_secret_path,
            )
            sys.exit(1)

        # Publish portal image and restart ECS
        account_id = tf_output["account_id"]["value"]
        ecr = boto3_session.client("ecr", region_name=aws_region)
        # Request an authorization token for your registry
        resp = ecr.get_authorization_token(registryIds=[account_id])
        data = resp["authorizationData"][0]

        # Decode "AWS:<password>"
        userpass = b64decode(data["authorizationToken"]).decode("utf-8")
        username, password = userpass.split(":", 1)

        # The registry host (strip scheme from proxyEndpoint)
        registry = data["proxyEndpoint"].replace("https://", "").replace("http://", "")
        run(
            ["docker", "login", "--username", username, "--password-stdin", registry],
            input=password.encode("utf-8"),
            check=True,
        )
        image_tag = f"{account_id}.dkr.ecr.{aws_region}.amazonaws.com/portal:latest"
        run(
            [
                "docker",
                "buildx",
                "build",
                "--platform",
                "linux/amd64",
                "-t",
                image_tag,
                "--push",
                ".",
            ],
            cwd="portal",
            check=True,
        )

        cluster_name = "openvpn-portal"
        service_name = "openvpn-portal"

        # Register task family for cleanup
        cleanup_ecs_task_definitions(service_name)

        ecs = boto3_session.client("ecs", region_name=aws_region)

        # Force new deployment
        ecs.update_service(
            cluster=cluster_name, service=service_name, forceNewDeployment=True
        )

        LOG.info("Restarting the portal service. Please wait...")

        # Wait until the service is stable
        ecs.get_waiter("services_stable").wait(
            cluster=cluster_name, services=[service_name]
        )
        LOG.info("Portal services restarted")
