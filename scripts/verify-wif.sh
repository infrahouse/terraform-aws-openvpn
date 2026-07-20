#!/usr/bin/env bash
#
# verify-wif.sh -- runtime verification of the keyless Google Workload Identity
# Federation (WIF) chain built by google-wif.tf.
#
# The pytest test (tests/test_google_wif.py) only asserts that the GCP-side
# *resources* exist. This script proves the *runtime handshake* actually works
# from a real AWS identity, one link at a time, so a failure pinpoints exactly
# which link is broken:
#
#   Tier 1  EC2/AWS identity matches the ARN the provider is locked to
#   Tier 2  federation exchange           AWS role      -> GCP federated token
#   Tier 3  service-account impersonation  federated id -> directory-reader SA
#   Tier 4  domain-wide delegation         SA           -> Workspace admin -> Directory API
#
# Run it ON the OpenVPN EC2 instance (e.g. over SSM). Tiers 1-3 need only what
# google-wif.tf creates; Tier 4 additionally needs the one manual step Terraform
# cannot do -- authorizing the SA's client id for the directory scope in the
# Workspace Admin console -- and a real admin subject, so it is opt-in.
#
# On a module-provisioned instance every value below is written by cloud-init to
# /opt/openvpn-wif/wif.env (see google-wif.tf), which this script sources on
# start. So the normal invocation is simply:  sudo /opt/openvpn-wif/verify-wif.sh
# The variables are documented only for running it by hand off-instance.
#
# Configuration (environment variables; explicit values override the env file):
#   WIF_PYTHON                     Python interpreter for Tiers 2-4. Default: the
#                                  infrahouse-toolkit embedded venv if present,
#                                  else system python3.
#   WIF_ENV_FILE                   Config file to source. Default: /opt/openvpn-wif/wif.env
#   GOOGLE_APPLICATION_CREDENTIALS  Path to the keyless credential config
#                                   (terraform output google_wif_credential_config_json).
#                                   Default: /opt/openvpn-wif/google-wif.json
#   WIF_SA_EMAIL                    Directory-reader SA email
#                                   (terraform output google_directory_reader_sa_email). Required.
#   WIF_SA_CLIENT_ID               Numeric OAuth client id of the SA, shown in the
#                                   Tier 4 domain-wide-delegation setup block.
#                                   (terraform output google_directory_reader_client_id).
#   WIF_EXPECTED_ROLE_ARN          Normalized assumed-role ARN the provider is locked to.
#                                   If set, Tier 1 asserts the instance matches it.
#   WIF_ADMIN_SUBJECT              Workspace admin the SA impersonates. If set, runs Tier 4.
#   WIF_DIRECTORY_SCOPE            Directory scope. Default: admin.directory.user.readonly.
#
# Exit status: non-zero if any required tier (1-3, and 4 when WIF_ADMIN_SUBJECT
# is set) fails.

set -euo pipefail

# Load the Terraform-provisioned config (SA email, locked role ARN, admin
# subject, credential path) that cloud-init wrote, so the operator supplies
# nothing -- the instance already knows every value. Explicit environment
# variables still win (they are set after this sources the file).
WIF_ENV_FILE="${WIF_ENV_FILE:-/opt/openvpn-wif/wif.env}"
if [ -f "$WIF_ENV_FILE" ]; then
    # shellcheck disable=SC1090
    . "$WIF_ENV_FILE"
fi

CRED_CONFIG="${GOOGLE_APPLICATION_CREDENTIALS:-/opt/openvpn-wif/google-wif.json}"
SA_EMAIL="${WIF_SA_EMAIL:-}"
EXPECTED_ROLE_ARN="${WIF_EXPECTED_ROLE_ARN:-}"
ADMIN_SUBJECT="${WIF_ADMIN_SUBJECT:-}"
DIRECTORY_SCOPE="${WIF_DIRECTORY_SCOPE:-https://www.googleapis.com/auth/admin.directory.user.readonly}"

export GOOGLE_APPLICATION_CREDENTIALS="$CRED_CONFIG"

# Prefer the infrahouse-toolkit embedded venv: it is a modern Python isolated
# from the system interpreter and the intended long-term home for the google
# deps. Fall back to system python3. Override with WIF_PYTHON. The install hint
# points at whichever venv is in use (embedded pip needs no --break-system-packages).
TOOLKIT_PYTHON="/opt/infrahouse-toolkit/embedded/bin/python3"
TOOLKIT_PIP="/opt/infrahouse-toolkit/embedded/bin/pip3"
if [ -n "${WIF_PYTHON:-}" ]; then
    PYTHON="$WIF_PYTHON"
elif [ -x "$TOOLKIT_PYTHON" ]; then
    PYTHON="$TOOLKIT_PYTHON"
else
    PYTHON="python3"
fi
if [ "$PYTHON" = "$TOOLKIT_PYTHON" ] && [ -x "$TOOLKIT_PIP" ]; then
    export WIF_PIP_HINT="$TOOLKIT_PIP install 'google-auth>=2' google-api-python-client"
else
    export WIF_PIP_HINT="pip3 install --break-system-packages 'google-auth>=2' google-api-python-client"
fi

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# --- Tier 1: AWS identity -----------------------------------------------------
# Prove the instance presents the exact assumed-role ARN the WIF provider's
# attribute_condition is locked to. IMDSv2 (token-first) per module design.
echo "=== Tier 1: AWS identity ==="
imds_token="$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60")" || fail "IMDSv2 token request failed"
role_name="$(curl -sf -H "X-aws-ec2-metadata-token: $imds_token" \
    "http://169.254.169.254/latest/meta-data/iam/security-credentials/")" \
    || fail "IMDS did not return an instance role"
echo "IMDS instance role: $role_name"

caller_arn="$(aws sts get-caller-identity --query Arn --output text)" \
    || fail "aws sts get-caller-identity failed"
echo "STS caller ARN:     $caller_arn"

# STS presents arn:aws:sts::ACCT:assumed-role/NAME/SESSION; the provider
# attribute_mapping normalizes that to assumed-role/NAME. Rebuild the normalized
# form here and compare, exactly as google-wif.tf does.
normalized_arn="$(printf '%s' "$caller_arn" | sed -E 's#:assumed-role/([^/]+)/.*#:assumed-role/\1#')"
echo "Normalized ARN:     $normalized_arn"
if [ -n "$EXPECTED_ROLE_ARN" ]; then
    [ "$normalized_arn" = "$EXPECTED_ROLE_ARN" ] \
        || fail "instance ARN '$normalized_arn' != expected '$EXPECTED_ROLE_ARN'"
    echo "PASS Tier 1: instance ARN matches the locked role"
else
    echo "PASS Tier 1: instance identity resolved (set WIF_EXPECTED_ROLE_ARN to assert a match)"
fi

# --- Tiers 2-4: Google side ---------------------------------------------------
[ -n "$SA_EMAIL" ] || fail "WIF_SA_EMAIL is required for Tiers 2-4"
[ -f "$CRED_CONFIG" ] || fail "credential config not found at $CRED_CONFIG"

"$PYTHON" - "$SA_EMAIL" "$DIRECTORY_SCOPE" "$ADMIN_SUBJECT" <<'PYEOF'
"""Tiers 2-4 of the WIF runtime check, using the google-auth libraries."""
import os
import sys

_INSTALL_HINT = (
    "  WIF needs google-auth >= 2.x (the distro apt python3-google-auth is 1.5.x,\n"
    "  far too old -- it has neither external_account nor impersonated_credentials).\n"
    "  Install into the interpreter this script uses:\n"
    "  " + os.environ.get(
        "WIF_PIP_HINT",
        "pip3 install --break-system-packages 'google-auth>=2' google-api-python-client",
    )
)

try:
    import google.auth
except ImportError:
    sys.exit(f"FAIL: google-auth is not installed.\n{_INSTALL_HINT}")

# Present but too old? The distro package imports as google.auth yet lacks the
# submodules the federation needs, so report that distinctly from "missing".
try:
    import google.auth.transport.requests as gt
    from google.auth import impersonated_credentials  # noqa: F401
except ImportError as error:
    version = getattr(google.auth, "__version__", "unknown")
    sys.exit(
        f"FAIL: google-auth is installed but too old for WIF "
        f"(version {version}): {error}.\n{_INSTALL_HINT}"
    )

sa_email, directory_scope, admin_subject = sys.argv[1], sys.argv[2], sys.argv[3]
sa_client_id = os.environ.get("WIF_SA_CLIENT_ID", "")
request = gt.Request()
cloud_platform = "https://www.googleapis.com/auth/cloud-platform"


def dwd_setup_block():
    """The exact values to paste into the Workspace Domain-Wide Delegation UI."""
    client = sa_client_id or "(missing from wif.env -- re-provision the instance)"
    return (
        "  Domain-wide delegation setup (one-time, requires a Workspace super admin):\n"
        "    1. Open https://admin.google.com/ac/owl/domainwidedelegation\n"
        "    2. Click 'Add new' and enter exactly:\n"
        f"         Client ID:    {client}\n"
        f"         OAuth scopes: {directory_scope}\n"
        "    3. Click Authorize."
    )

# Tier 2: federation exchange -- the keyless AWS -> GCP handshake.
print("=== Tier 2: federation exchange (AWS role -> GCP token) ===")
source, _ = google.auth.default(scopes=[cloud_platform])
source.refresh(request)
print("PASS Tier 2: federated token minted:", source.token[:22], "...")

# Tier 3: impersonate the directory-reader SA -- proves the workloadIdentityUser
# and serviceAccountTokenCreator bindings are effective.
print("=== Tier 3: impersonate directory-reader SA ===")
sa_credentials = impersonated_credentials.Credentials(
    source_credentials=source,
    target_principal=sa_email,
    target_scopes=[directory_scope],
)
sa_credentials.refresh(request)
print("PASS Tier 3: SA-impersonation token minted:", sa_credentials.token[:22], "...")

# Tier 4: domain-wide delegation -> Directory API. Opt-in: needs a real admin
# subject AND the manual DWD authorization in the Workspace Admin console.
print("=== Tier 4: domain-wide delegation -> Directory API ===")

# The setup block is printed only when it is actionable (skipped or rejected) --
# not on success, where it would be pure noise.
if not admin_subject:
    print("SKIP Tier 4: WIF_ADMIN_SUBJECT is empty; set it to a real Workspace admin to test the call.")
    print(dwd_setup_block())
    sys.exit(0)

from googleapiclient.discovery import build

from google.auth.exceptions import RefreshError

dwd_credentials = impersonated_credentials.Credentials(
    source_credentials=source,
    target_principal=sa_email,
    target_scopes=[directory_scope],
    subject=admin_subject,
)
directory = build("admin", "directory_v1", credentials=dwd_credentials, cache_discovery=False)
try:
    response = directory.users().list(
        customer="my_customer", query="isSuspended=true", maxResults=5
    ).execute()
except RefreshError as error:
    # Rejected until the client id above is authorized for the scope AND
    # admin_subject is a real user in that Workspace.
    sys.exit(
        f"FAIL Tier 4: domain-wide delegation rejected ({error.args[0]}).\n"
        f"  Subject: {admin_subject}\n"
        f"{dwd_setup_block()}\n"
        f"  Then re-run (authorization takes a few minutes to propagate)."
    )
suspended = [user["primaryEmail"] for user in response.get("users", [])]
print("PASS Tier 4: read suspended users via DWD:", suspended)
PYEOF

echo "=== All requested tiers passed ==="
