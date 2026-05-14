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


def wait_for_puppet(instance, timeout=600, poll_interval=10):
    """
    Wait for Puppet bootstrap to complete on an instance.

    Puppet completion is indicated by the marker file /var/run/puppet-done.

    :param instance: EC2 instance to check
    :param timeout: Maximum time to wait in seconds (default: 600 = 10 minutes)
    :param poll_interval: Time between checks in seconds (default: 10)
    :raises AssertionError: If Puppet does not complete within timeout
    """
    LOG.info("Waiting for Puppet to complete bootstrap (up to %d seconds)...", timeout)

    for attempt in range(timeout // poll_interval):
        exit_code, stdout, stderr = instance.execute_command(
            "test -f /var/run/puppet-done && echo 'done' || echo 'not done'"
        )

        if exit_code == 0 and stdout.strip() == "done":
            LOG.info(
                f"✓ Puppet bootstrap completed (after {(attempt + 1) * poll_interval} seconds)"
            )
            return

        LOG.info(
            f"   Puppet still running (attempt {attempt + 1}/{timeout // poll_interval})..."
        )
        time.sleep(poll_interval)

    raise AssertionError(
        f"Puppet bootstrap did not complete after {timeout} seconds. "
        f"Marker file /var/run/puppet-done not found. "
        f"Instance may still be bootstrapping or bootstrap failed."
    )


def verify_cloudwatch_logging(instance, log_group_name, boto3_session, aws_region):
    """
    Verify CloudWatch logging infrastructure created by this Terraform module.

    Tests that:
    1. CloudWatch Log Group exists in AWS (created by Terraform)
    2. Instance has IAM permissions to create log streams
    3. Instance has IAM permissions to write log events
    4. Logs written from instance are readable via CloudWatch API

    This test is independent of Puppet configuration - it directly tests
    the infrastructure (log group, IAM permissions) created by Terraform.

    :param instance: EC2 instance to verify
    :param log_group_name: CloudWatch log group name (from Terraform output)
    :param boto3_session: Boto3 session for creating AWS clients
    :param aws_region: AWS region
    """
    import uuid

    LOG.info("Testing CloudWatch logging infrastructure...")
    LOG.info("Instance: %s", instance.instance_id)
    LOG.info("Log group: %s", log_group_name)

    logs_client = boto3_session.client("logs", region_name=aws_region)

    # 1. Verify CloudWatch Log Group exists in AWS
    LOG.info("1. Verifying CloudWatch Log Group exists...")
    try:
        response = logs_client.describe_log_groups(
            logGroupNamePrefix=log_group_name, limit=1
        )
        log_groups = response.get("logGroups", [])
        assert len(log_groups) > 0, f"Log group {log_group_name} not found"

        log_group = log_groups[0]
        assert (
            log_group["logGroupName"] == log_group_name
        ), f"Log group name mismatch: {log_group['logGroupName']} != {log_group_name}"

        LOG.info("✓ CloudWatch Log Group exists: %s", log_group_name)
        LOG.info(
            "  Retention: %s days", log_group.get("retentionInDays", "Never expire")
        )

    except Exception as e:
        pytest.fail(f"Failed to verify CloudWatch Log Group: {e}")

    # 2. Test instance can create log stream and write logs using AWS CLI
    LOG.info("2. Testing instance can write to CloudWatch Logs...")

    test_stream_name = f"test-{instance.instance_id}-{uuid.uuid4().hex[:8]}"
    test_message = f"TEST_MESSAGE_{uuid.uuid4().hex}"
    timestamp_ms = int(time.time() * 1000)

    # Create log stream from instance
    LOG.info("  Creating log stream: %s", test_stream_name)
    exit_code, stdout, stderr = instance.execute_command(
        f"aws logs create-log-stream "
        f"--log-group-name '{log_group_name}' "
        f"--log-stream-name '{test_stream_name}' "
        f"--region {aws_region}"
    )
    assert exit_code == 0, (
        f"Instance failed to create log stream. "
        f"This indicates missing IAM permissions. stderr: {stderr}"
    )
    LOG.info("✓ Instance created log stream successfully")

    # Write log event from instance
    LOG.info("  Writing test message to log stream...")
    exit_code, stdout, stderr = instance.execute_command(
        f"aws logs put-log-events "
        f"--log-group-name '{log_group_name}' "
        f"--log-stream-name '{test_stream_name}' "
        f"--log-events 'timestamp={timestamp_ms},message={test_message}' "
        f"--region {aws_region}"
    )
    assert exit_code == 0, (
        f"Instance failed to write log event. "
        f"This indicates missing IAM permissions. stderr: {stderr}"
    )
    LOG.info("✓ Instance wrote log event successfully")

    # 3. Read log event from pytest to verify end-to-end
    LOG.info("3. Verifying log event is readable from CloudWatch API...")

    max_wait = 30
    poll_interval = 5
    message_found = False

    for attempt in range(max_wait // poll_interval):
        time.sleep(poll_interval)

        try:
            response = logs_client.get_log_events(
                logGroupName=log_group_name,
                logStreamName=test_stream_name,
                limit=10,
            )

            for event in response.get("events", []):
                if test_message in event.get("message", ""):
                    message_found = True
                    LOG.info(
                        "✓ Test message found in CloudWatch after %d seconds",
                        (attempt + 1) * poll_interval,
                    )
                    break

            if message_found:
                break

        except logs_client.exceptions.ResourceNotFoundException:
            LOG.info(
                "  Log stream not visible yet (attempt %d/%d)...",
                attempt + 1,
                max_wait // poll_interval,
            )
            continue

    assert message_found, (
        f"Test message not found in CloudWatch after {max_wait} seconds. "
        f"Log group: {log_group_name}, Log stream: {test_stream_name}."
    )

    # 4. Verify instance CANNOT delete log streams (least privilege)
    LOG.info("4. Verifying instance cannot delete log streams (least privilege)...")
    exit_code, stdout, stderr = instance.execute_command(
        f"aws logs delete-log-stream "
        f"--log-group-name '{log_group_name}' "
        f"--log-stream-name '{test_stream_name}' "
        f"--region {aws_region} 2>&1 || true"
    )
    # Should fail with AccessDenied
    assert (
        "AccessDenied" in stderr or "AccessDeniedException" in stdout or exit_code != 0
    ), (
        "Instance was able to delete log stream! "
        "IAM policy grants excessive permissions - should only allow create/write."
    )
    LOG.info("✓ Instance correctly denied permission to delete log stream")

    # 5. Cleanup from pytest (has broader permissions)
    LOG.info("5. Cleaning up test log stream...")
    try:
        logs_client.delete_log_stream(
            logGroupName=log_group_name, logStreamName=test_stream_name
        )
        LOG.info("✓ Test log stream deleted")
    except Exception as e:
        LOG.warning("Failed to delete test log stream: %s", e)

    LOG.info("✅ CloudWatch logging infrastructure verified!")
    LOG.info("  - Log group exists and is accessible")
    LOG.info("  - Instance has IAM permissions to create log streams")
    LOG.info("  - Instance has IAM permissions to write log events")
    LOG.info("  - Logs are readable via CloudWatch API")


@pytest.mark.parametrize("aws_provider_version", ["~> 6.0"], ids=["aws6"])
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

        # Get instance from ASG for testing
        asg = ASG(
            asg_name,
            region=aws_region,
            role_arn=test_role_arn,
        )
        instances = list(asg.instances)
        assert len(instances) > 0, "No instances found in ASG"
        instance = instances[0]

        # Wait for Puppet bootstrap to complete
        wait_for_puppet(instance)

        # Test CloudWatch Logging Configuration
        log_group_name = tf_output["cloudwatch_log_group_name"]["value"]
        verify_cloudwatch_logging(
            instance=instance,
            log_group_name=log_group_name,
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
