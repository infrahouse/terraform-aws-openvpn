import json
import os
import sys
import time
from base64 import b64decode
from os import path as osp
from subprocess import check_call, run
from textwrap import dedent

import pytest
from infrahouse_core.aws.asg import ASG
from pytest_infrahouse import terraform_apply
from pytest_infrahouse.utils import wait_for_instance_refresh

from tests.conftest import (
    LOG,
    TERRAFORM_ROOT_DIR,
)


def test_cloudwatch_logging(asg, boto3_session, aws_region):
    """
    Test CloudWatch logging end-to-end integration for OpenVPN instances.

    Validates:
    1. CloudWatch log group is configured via Puppet facts
    2. CloudWatch agent service is running (managed by Puppet)
    3. CloudWatch Log Group exists in AWS
    4. End-to-end: logs written on instance appear in CloudWatch

    Note: CloudWatch agent package, configuration, and service management
    are Puppet's responsibility. Terraform only tests the end result.

    :param asg: ASG instance
    :param boto3_session: Boto3 session for creating AWS clients
    :param aws_region: AWS region
    """
    LOG.info("Testing CloudWatch logging end-to-end integration...")

    # Get an instance from the ASG
    instances = list(asg.instances)
    assert len(instances) > 0, "No instances found in ASG"

    instance = instances[0]
    LOG.info("Testing CloudWatch logging on instance: %s", instance.instance_id)

    # 1. Verify CloudWatch log group is in Puppet facts
    LOG.info("1. Checking Puppet facts for CloudWatch log group...")
    exit_code, stdout, stderr = instance.execute_command(
        "sudo facter -p openvpn.cloudwatch_log_group"
    )
    log_group_name = stdout.strip()
    assert (
        log_group_name
    ), f"CloudWatch log group not found in Puppet facts. stderr: {stderr}"
    assert log_group_name.startswith(
        "/aws/openvpn/"
    ), f"Invalid log group name format: {log_group_name}"
    LOG.info("✓ CloudWatch log group in Puppet facts: %s", log_group_name)

    # 2. Verify CloudWatch agent service is running (Puppet's responsibility)
    LOG.info("2. Verifying CloudWatch agent service is running...")
    exit_code, stdout, stderr = instance.execute_command(
        "systemctl is-active amazon-cloudwatch-agent"
    )
    assert exit_code == 0, f"CloudWatch agent service not running. stderr: {stderr}"
    LOG.info("✓ CloudWatch agent service is active")

    # 3. Verify CloudWatch Log Group exists in AWS
    LOG.info("3. Verifying CloudWatch Log Group exists in AWS...")
    logs_client = boto3_session.client("logs", region_name=aws_region)

    try:
        response = logs_client.describe_log_groups(
            logGroupNamePrefix=log_group_name, limit=1
        )
        log_groups = response.get("logGroups", [])
        assert (
            len(log_groups) > 0
        ), f"Log group {log_group_name} not found in CloudWatch"

        log_group = log_groups[0]
        assert (
            log_group["logGroupName"] == log_group_name
        ), f"Log group name mismatch: {log_group['logGroupName']} != {log_group_name}"

        LOG.info("✓ CloudWatch Log Group exists: %s", log_group_name)

        # Check if KMS encryption is enabled (optional)
        if "kmsKeyId" in log_group:
            LOG.info("  KMS Key: %s", log_group["kmsKeyId"])
        else:
            LOG.info("  Encryption: Default server-side encryption")

        LOG.info(
            "  Retention: %s days", log_group.get("retentionInDays", "Never expire")
        )

    except Exception as e:
        pytest.fail(f"Failed to verify CloudWatch Log Group: {e}")

    # 4. Verify end-to-end logging: write log on instance, verify it appears in CloudWatch
    LOG.info("4. Verifying end-to-end CloudWatch Logs integration...")

    # Generate unique test message
    import uuid

    test_message = f"TEST_LOG_MESSAGE_{uuid.uuid4().hex}"
    log_stream_name = f"{instance.instance_id}/auth.log"

    # Write test message to auth.log (which is configured to ship to CloudWatch)
    LOG.info("  Writing test message to /var/log/auth.log...")
    exit_code, stdout, stderr = instance.execute_command(
        f'echo "{test_message}" | sudo tee -a /var/log/auth.log'
    )
    assert exit_code == 0, f"Failed to write test message. stderr: {stderr}"

    # Give CloudWatch agent time to ship the log (it batches and sends periodically)
    LOG.info("  Waiting for log to appear in CloudWatch (up to 60 seconds)...")
    max_wait = 60
    poll_interval = 5
    message_found = False

    for attempt in range(max_wait // poll_interval):
        time.sleep(poll_interval)

        try:
            # Read recent log events from the log stream
            response = logs_client.get_log_events(
                logGroupName=log_group_name,
                logStreamName=log_stream_name,
                limit=100,
                startFromHead=False,  # Get most recent events
            )

            # Check if our test message appears in the log events
            for event in response.get("events", []):
                if test_message in event.get("message", ""):
                    message_found = True
                    LOG.info(
                        f"  ✓ Test message found in CloudWatch after {(attempt + 1) * poll_interval} seconds"
                    )
                    break

            if message_found:
                break

        except logs_client.exceptions.ResourceNotFoundException:
            # Log stream might not exist yet - CloudWatch agent creates it on first write
            LOG.info(
                f"  Log stream not found yet (attempt {attempt + 1}/{max_wait // poll_interval})..."
            )
            continue

    assert message_found, (
        f"Test message not found in CloudWatch Logs after {max_wait} seconds. "
        f"Log group: {log_group_name}, Log stream: {log_stream_name}. "
        f"This indicates the CloudWatch agent is not successfully shipping logs."
    )

    LOG.info("✓ End-to-end CloudWatch Logs integration verified")
    LOG.info("  - Instance can write logs")
    LOG.info("  - CloudWatch agent ships logs to CloudWatch")
    LOG.info("  - Logs are readable via CloudWatch Logs API")

    LOG.info("✅ All CloudWatch logging tests passed!")


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
                region       = "{aws_region}"
                test_zone    = "{test_zone_name}"

                lb_subnet_ids      = {json.dumps(subnet_public_ids)}
                backend_subnet_ids = {json.dumps(subnet_public_ids)}
                """
            )
        )
        if test_role_arn:
            fp.write(
                dedent(
                    f"""
                    role_arn = "{test_role_arn}"
                    """
                )
            )

    LOG.info("Testing with AWS provider version: %s", aws_provider_version)

    with terraform_apply(
        terraform_module_dir,
        destroy_after=not keep_after,
    ) as tf_output:
        LOG.info("%s", json.dumps(tf_output, indent=4))

        # Register ECS task clean up early to ensure it runs if there are test failures.
        cluster_name = "openvpn-portal"
        service_name = "openvpn-portal"

        # Register task family for cleanup
        cleanup_ecs_task_definitions(service_name)

        # update Google OAuth 2.0 Client IDs
        google_client_secret = tf_output["google_client_secret"]["value"]
        portal_url = tf_output["portal_url"]["value"]

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

        # Wait for instance refresh to complete before testing
        asg_name = tf_output["autoscaling_group_name"]["value"]
        autoscaling_client = boto3_session.client("autoscaling", region_name=aws_region)
        wait_for_instance_refresh(
            asg_name=asg_name,
            autoscaling_client=autoscaling_client,
            timeout=1800,  # 30 minutes
        )

        # Test CloudWatch Logging Configuration
        asg = ASG(
            asg_name,
            region=aws_region,
            role_arn=test_role_arn,
        )
        test_cloudwatch_logging(
            asg=asg,
            boto3_session=boto3_session,
            aws_region=aws_region,
        )

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
        LOG.info("Portal URL: %s", tf_output["portal_url"]["value"])
