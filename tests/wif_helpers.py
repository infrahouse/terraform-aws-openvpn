"""
Helpers for verifying the Google Workload Identity Federation (WIF) side of the
openvpn module (``enable_google_directory_revocation = true``).

Since v7.0.0 the module always requires a ``google`` provider, so the module
cannot be applied without working GCP credentials. These helpers therefore
**fail** (not skip) when credentials are missing or unusable -- an environment
that cannot reach GCP cannot exercise the module at all.

Used by ``tests/test_module.py``, which stands the module up once and verifies
both the AWS side and the keyless federation on GCP:

* the directory-reader service account exists and has **no** user-managed keys,
* the workload identity pool and its AWS provider exist and are ACTIVE,
* the SA grants ``workloadIdentityUser`` and ``serviceAccountTokenCreator`` to a
  ``principalSet`` scoped to that pool.
"""

import json
import os

import pytest

from tests.conftest import LOG

CLOUD_PLATFORM_SCOPE = "https://www.googleapis.com/auth/cloud-platform"
WORKLOAD_IDENTITY_USER_ROLE = "roles/iam.workloadIdentityUser"
TOKEN_CREATOR_ROLE = "roles/iam.serviceAccountTokenCreator"


def google_credentials():
    """
    Resolve Google ADC and the target project, failing the test if unavailable.

    The openvpn module requires a configured google provider (v7.0.0+), so a run
    without GCP credentials cannot apply the module -- that is a failure, not a
    skip.

    :return: Tuple of (credentials, project_id).
    :rtype: tuple
    """
    # Imported lazily so importing this module does not require the Google
    # libraries when they are not needed.
    from google.auth import default as google_auth_default
    from google.auth.exceptions import DefaultCredentialsError

    # Resolve the project up front so we can hand it to google.auth.default as
    # the quota project. That is the project everything targets anyway, and
    # supplying it silences google-auth's spurious "no quota project" warning.
    project = os.environ.get("GOOGLE_PROJECT") or os.environ.get("GOOGLE_CLOUD_PROJECT")

    try:
        credentials, adc_project = google_auth_default(
            scopes=[CLOUD_PLATFORM_SCOPE], quota_project_id=project
        )
    except DefaultCredentialsError:
        pytest.fail(
            "No Google Application Default Credentials, but the openvpn module "
            "requires a google provider (v7.0.0+). Run "
            "`gcloud auth application-default login` locally, or configure "
            "google-github-actions/auth in CI."
        )

    project = project or adc_project
    if not project:
        pytest.fail(
            "No GCP project resolved. Set GOOGLE_PROJECT (or a quota project on "
            "your ADC)."
        )

    _verify_credentials_usable(credentials, project)

    return credentials, project


def _verify_credentials_usable(credentials, project):
    """
    Prove the resolved credentials actually work before any infrastructure is
    built.

    Resolving ADC only proves credentials *exist*; it does not prove they can
    still call an API. Expired reauth (RAPT) tokens resolve fine and then fail at
    the first sensitive call, so without this check the run dies many minutes in
    -- after building the full stack -- on an opaque ``invalid_rapt``. Calling
    the same API Terraform hits first (serviceusage) surfaces it in about a
    second.

    :param credentials: Google ADC credentials.
    :param project: GCP project id the test runs against.
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
    # printed is a false alarm: everything targets the project explicitly, so no
    # ADC quota project is needed. Say so, next to the warning.
    LOG.info(
        "✓ Google credentials verified against %s. Ignore any 'quota project' "
        "warning above -- the project is passed explicitly, none is needed.",
        project,
    )


def iam_service(credentials):
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
    so the caller never has to reconstruct them.

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


def verify_google_wif(tf_output, credentials):
    """
    Run the full WIF verification against a module's terraform output.

    :param tf_output: The parsed ``terraform output`` of a stack that has
        ``enable_google_directory_revocation = true``.
    :param credentials: Google ADC credentials (from ``google_credentials()``).
    """
    iam = iam_service(credentials)

    sa_email = tf_output["google_directory_reader_sa_email"]["value"]
    client_id = tf_output["google_directory_reader_client_id"]["value"]
    cred_config = json.loads(tf_output["google_wif_credential_config_json"]["value"])
    pool_id = tf_output["wif_pool_id"]["value"]
    provider_id = tf_output["wif_provider_id"]["value"]
    sa_id = tf_output["wif_sa_id"]["value"]

    # --- Output shape checks (cheap, no API calls) --------------------------
    assert sa_email.startswith(f"{sa_id}@")
    assert sa_email.endswith(".iam.gserviceaccount.com")
    assert str(client_id).isdigit(), f"client_id is not numeric: {client_id}"
    verify_credential_config(cred_config, pool_id, provider_id)

    # --- Live GCP-side verification -----------------------------------------
    verify_service_account(iam, sa_email)
    verify_no_user_managed_keys(iam, sa_email)
    pool_name = verify_pool_and_provider(iam, cred_config["audience"])
    verify_sa_iam_bindings(iam, sa_email, pool_name)
    LOG.info("✅ Google WIF verified end-to-end")
