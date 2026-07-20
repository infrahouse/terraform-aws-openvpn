"""
Integration test for the Google Workload Identity Federation (WIF) feature
defined in ``google-wif.tf`` (``enable_google_directory_revocation = true``).

It stands up the ``openvpn`` module against a real AWS account **and** a real
GCP project, then verifies -- with the Google API client libraries -- that the
keyless federation was created correctly on the GCP side:

* the directory-reader service account exists and has **no** user-managed keys
  (the whole point of WIF is "no key at rest"),
* the workload identity pool and its AWS provider exist and are ACTIVE,
* the SA grants ``workloadIdentityUser`` and ``serviceAccountTokenCreator`` to a
  ``principalSet`` scoped to that pool.

Authentication uses Application Default Credentials (ADC) for both Terraform's
``google`` provider and this test's API calls, so the same test runs locally
(``gcloud auth application-default login``) and in GitHub Actions
(``google-github-actions/auth``). If no ADC / project is available the test is
skipped rather than failed.
"""

import json
import os
from os import path as osp
from subprocess import check_call
from textwrap import dedent

import pytest
from pytest_infrahouse import terraform_apply
from pytest_infrahouse.utils import wait_for_instance_refresh

from tests.conftest import (
    LOG,
    TERRAFORM_ROOT_DIR,
)

CLOUD_PLATFORM_SCOPE = "https://www.googleapis.com/auth/cloud-platform"
WORKLOAD_IDENTITY_USER_ROLE = "roles/iam.workloadIdentityUser"
TOKEN_CREATOR_ROLE = "roles/iam.serviceAccountTokenCreator"


def _google_credentials():
    """
    Resolve Google ADC and the target project, or skip the test.

    :return: Tuple of (credentials, project_id).
    :rtype: tuple
    """
    # Imported lazily so the rest of the suite does not require the Google
    # libraries to be installed.
    from google.auth import default as google_auth_default
    from google.auth.exceptions import DefaultCredentialsError

    # Resolve the project up front so we can hand it to google.auth.default as
    # the quota project. That is the project everything targets anyway, and
    # supplying it is what silences google-auth's "no quota project" warning --
    # no `gcloud set-quota-project` (which mutates global ADC state) required.
    project = os.environ.get("GOOGLE_PROJECT") or os.environ.get("GOOGLE_CLOUD_PROJECT")

    try:
        credentials, adc_project = google_auth_default(
            scopes=[CLOUD_PLATFORM_SCOPE], quota_project_id=project
        )
    except DefaultCredentialsError:
        pytest.skip(
            "No Google Application Default Credentials. Run "
            "`gcloud auth application-default login` locally, or configure "
            "google-github-actions/auth in CI."
        )

    project = project or adc_project
    if not project:
        pytest.skip(
            "No GCP project resolved. Set GOOGLE_PROJECT (or configure a "
            "quota project on your ADC)."
        )

    _verify_credentials_usable(credentials, project)

    return credentials, project


def _verify_credentials_usable(credentials, project):
    """
    Prove the resolved credentials actually work before any infrastructure is
    built.

    Resolving ADC only proves credentials *exist*; it does not prove they can
    still call an API. Expired reauth (RAPT) tokens resolve fine and then fail
    at the first sensitive call, so without this check the run dies ~6 minutes
    in -- after creating a hundred-plus AWS resources -- on an opaque
    ``invalid_rapt``. Calling the same API Terraform hits first (serviceusage,
    to enable the required APIs) surfaces that in about a second.

    :param credentials: Google ADC credentials.
    :param project: GCP project id the test runs against.
    :raise Failed: if the credentials cannot call the serviceusage API.
    """
    from google.auth.exceptions import RefreshError
    from googleapiclient.discovery import build
    from googleapiclient.errors import HttpError

    try:
        build(
            "serviceusage", "v1", credentials=credentials, cache_discovery=False
        ).services().list(
            parent=f"projects/{project}", filter="state:ENABLED", pageSize=1
        ).execute()
    except RefreshError as error:
        pytest.fail(
            f"Google credentials resolved but cannot be refreshed: {error}\n"
            "Reauth (RAPT) tokens expire periodically -- run "
            "`gcloud auth application-default login` and retry."
        )
    except HttpError as error:
        pytest.fail(
            f"Google credentials work but cannot list services in {project}: {error}\n"
            "The identity needs roles/serviceusage.serviceUsageAdmin (plus "
            "iam.serviceAccountAdmin and iam.workloadIdentityPoolAdmin) in that project."
        )

    # The call above just succeeded, so any "quota project" warning google-auth
    # printed is a false alarm: this test (and the google provider) target the
    # project explicitly, so no ADC quota project is needed. Say so, next to the
    # warning, to save the reader a `set-quota-project` detour.
    LOG.info(
        "✓ Google credentials verified against %s. Ignore any 'quota project' "
        "warning above -- the project is passed explicitly, none is needed.",
        project,
    )


def _iam_service(credentials):
    """
    Build the IAM v1 API client used for all GCP-side assertions.

    :param credentials: Google ADC credentials.
    :return: Discovery client for the IAM v1 API.
    """
    from googleapiclient.discovery import build

    return build("iam", "v1", credentials=credentials, cache_discovery=False)


def verify_service_account(iam, sa_email):
    """
    Verify the directory-reader service account exists and is enabled.

    :param iam: IAM v1 API client.
    :param sa_email: Email of the service account to check.
    """
    LOG.info("Verifying service account %s exists...", sa_email)
    account = (
        iam.projects()
        .serviceAccounts()
        .get(name=f"projects/-/serviceAccounts/{sa_email}")
        .execute()
    )
    assert account["email"] == sa_email
    assert not account.get("disabled", False), f"Service account {sa_email} is disabled"
    LOG.info("✓ Service account exists and is enabled")


def verify_no_user_managed_keys(iam, sa_email):
    """
    Verify the SA has no user-managed keys -- the keyless (WIF) invariant.

    :param iam: IAM v1 API client.
    :param sa_email: Email of the service account to check.
    """
    LOG.info("Verifying %s has no user-managed keys...", sa_email)
    response = (
        iam.projects()
        .serviceAccounts()
        .keys()
        .list(
            name=f"projects/-/serviceAccounts/{sa_email}",
            keyTypes="USER_MANAGED",
        )
        .execute()
    )
    keys = response.get("keys", [])
    assert not keys, (
        f"Service account {sa_email} has {len(keys)} user-managed key(s); "
        f"WIF must be keyless."
    )
    LOG.info("✓ No user-managed keys (keyless as designed)")


def verify_pool_and_provider(iam, audience):
    """
    Verify the workload identity pool and its AWS provider exist and are ACTIVE.

    The full resource names are parsed out of the credential-config ``audience``
    (``//iam.googleapis.com/projects/N/locations/global/workloadIdentityPools/POOL/providers/PROVIDER``)
    so the test never has to reconstruct them.

    :param iam: IAM v1 API client.
    :param audience: The ``audience`` field from the WIF credential config.
    :return: The pool's full resource name (``projects/.../workloadIdentityPools/POOL``).
    :rtype: str
    """
    prefix = "//iam.googleapis.com/"
    assert audience.startswith(prefix), f"Unexpected audience format: {audience}"
    provider_name = audience[len(prefix) :]
    pool_name = provider_name.split("/providers/")[0]

    LOG.info("Verifying workload identity pool %s...", pool_name)
    pool = (
        iam.projects().locations().workloadIdentityPools().get(name=pool_name).execute()
    )
    assert (
        pool.get("state") == "ACTIVE"
    ), f"Pool {pool_name} is not ACTIVE: {pool.get('state')}"
    LOG.info("✓ Pool exists and is ACTIVE")

    LOG.info("Verifying pool provider %s...", provider_name)
    provider = (
        iam.projects()
        .locations()
        .workloadIdentityPools()
        .providers()
        .get(name=provider_name)
        .execute()
    )
    assert (
        provider.get("state") == "ACTIVE"
    ), f"Provider {provider_name} is not ACTIVE: {provider.get('state')}"
    # The module locks federation to one AWS role via an attribute condition.
    assert provider.get(
        "attributeCondition"
    ), "Provider is missing its attribute_condition (federation is not locked down)"
    assert "aws" in provider, "Provider is not configured for AWS"
    LOG.info("✓ Provider exists, is ACTIVE, and is locked to the AWS role")

    return pool_name


def verify_sa_iam_bindings(iam, sa_email, pool_name):
    """
    Verify the SA delegates both required roles to a principalSet in the pool.

    :param iam: IAM v1 API client.
    :param sa_email: Email of the service account to check.
    :param pool_name: Full resource name of the workload identity pool.
    """
    LOG.info("Verifying IAM bindings on %s...", sa_email)
    policy = (
        iam.projects()
        .serviceAccounts()
        .getIamPolicy(resource=f"projects/-/serviceAccounts/{sa_email}")
        .execute()
    )
    members_by_role = {
        binding["role"]: binding.get("members", [])
        for binding in policy.get("bindings", [])
    }

    expected_member_prefix = (
        f"principalSet://iam.googleapis.com/{pool_name}/attribute.aws_role/"
    )
    for role in (WORKLOAD_IDENTITY_USER_ROLE, TOKEN_CREATOR_ROLE):
        members = members_by_role.get(role, [])
        assert any(member.startswith(expected_member_prefix) for member in members), (
            f"{role} is not granted to a principalSet in pool {pool_name}. "
            f"Members: {members}"
        )
    LOG.info("✓ Both workloadIdentityUser and serviceAccountTokenCreator are bound")


def verify_credential_config(cred_config, expected_pool_id, expected_provider_id):
    """
    Verify the emitted credential config is a valid, secret-free WIF config.

    :param cred_config: Parsed ``google_wif_credential_config_json`` output.
    :param expected_pool_id: The pool id passed to the module.
    :param expected_provider_id: The provider id passed to the module.
    """
    assert cred_config["type"] == "external_account"
    assert (
        cred_config["subject_token_type"]
        == "urn:ietf:params:aws:token-type:aws4_request"
    )
    assert cred_config["credential_source"]["environment_id"] == "aws1"
    assert f"workloadIdentityPools/{expected_pool_id}" in cred_config["audience"]
    assert f"providers/{expected_provider_id}" in cred_config["audience"]
    # It must be keyless: no private key or other secret material.
    assert "private_key" not in cred_config
    assert "service_account_impersonation" not in json.dumps(cred_config)


def test_google_wif(
    service_network,
    aws_region,
    test_role_arn,
    test_zone_name,
    boto3_session,
    keep_after,
):
    credentials, google_project = _google_credentials()
    iam = _iam_service(credentials)

    subnet_public_ids = service_network["subnet_public_ids"]["value"]
    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "google_wif")

    # The unique per-environment suffix for the pool/provider/SA ids is owned by
    # Terraform (random_string in the test root), which avoids GCP's ~30-day
    # soft-delete id collisions. The concrete ids come back as outputs below.
    admin_email = os.environ.get("GOOGLE_WORKSPACE_ADMIN_EMAIL", "aleks@infrahouse.com")

    # Clean up any stale local state/lock from a previous run.
    check_call(
        ["rm", "-rf", ".terraform", ".terraform.lock.hcl"], cwd=terraform_module_dir
    )

    with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
        fp.write(dedent(f"""
                region    = "{aws_region}"
                test_zone = "{test_zone_name}"

                lb_subnet_ids      = {json.dumps(subnet_public_ids)}
                backend_subnet_ids = {json.dumps(subnet_public_ids)}

                google_project               = "{google_project}"
                google_workspace_admin_email = "{admin_email}"
                """))
        if test_role_arn:
            # Blank line first: terraform fmt aligns "=" per contiguous block, so
            # appending onto the block above would make the file fail fmt -check.
            fp.write(f'\nrole_arn = "{test_role_arn}"\n')

    LOG.info("Testing Google WIF in GCP project: %s", google_project)

    with terraform_apply(
        terraform_module_dir,
        destroy_after=not keep_after,
        json_output=True,
    ) as tf_output:
        LOG.info("%s", json.dumps(tf_output, indent=4))

        # Cloud-init writes the WIF files (cred config, wif.env, verify-wif.sh)
        # onto the OpenVPN instances. On a re-apply the launch template changes
        # and the ASG rolls instances; wait for that to settle before relying on
        # the instances. On a first apply there is no refresh and this returns
        # immediately.
        autoscaling_client = boto3_session.client("autoscaling", region_name=aws_region)
        wait_for_instance_refresh(
            asg_name=tf_output["autoscaling_group_name"]["value"],
            autoscaling_client=autoscaling_client,
            timeout=1800,  # 30 minutes
        )

        sa_email = tf_output["google_directory_reader_sa_email"]["value"]
        client_id = tf_output["google_directory_reader_client_id"]["value"]
        cred_config = json.loads(
            tf_output["google_wif_credential_config_json"]["value"]
        )
        pool_id = tf_output["wif_pool_id"]["value"]
        provider_id = tf_output["wif_provider_id"]["value"]
        sa_id = tf_output["wif_sa_id"]["value"]

        # --- Output shape checks (cheap, no API calls) ----------------------
        assert sa_email.startswith(f"{sa_id}@")
        assert sa_email.endswith(".iam.gserviceaccount.com")
        assert str(client_id).isdigit(), f"client_id is not numeric: {client_id}"
        verify_credential_config(cred_config, pool_id, provider_id)

        # --- Live GCP-side verification -------------------------------------
        verify_service_account(iam, sa_email)
        verify_no_user_managed_keys(iam, sa_email)
        pool_name = verify_pool_and_provider(iam, cred_config["audience"])
        verify_sa_iam_bindings(iam, sa_email, pool_name)

        LOG.info("✅ Google WIF verified end-to-end")
