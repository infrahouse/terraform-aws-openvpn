#!/usr/bin/env bash
#
# setup-ci-gcp-auth.sh -- one-time GCP setup so GitHub Actions CI can authenticate
# to GCP keylessly, via Workload Identity Federation over GitHub's OIDC token.
# This mirrors how CI already federates into AWS (aws-actions/configure-aws-
# credentials + role-to-assume) -- no service-account key is stored anywhere.
#
# Run it yourself with an account that has IAM admin on the project (it creates a
# pool, a provider, a service account, and IAM bindings). It is idempotent, so
# re-running is safe.
#
# After it prints the two values at the end, add this step to
# .github/workflows/terraform-CI.yml (after "Configure AWS Credentials"):
#
#     - name: Configure GCP Credentials
#       uses: google-github-actions/auth@v2
#       with:
#         workload_identity_provider: "<workload_identity_provider from below>"
#         service_account: "<service_account from below>"
#
# Configuration (environment variables; all have defaults):
#   GOOGLE_PROJECT        GCP project. Default: openvpn-427715
#   GITHUB_REPO           org/repo allowed to federate. Default: infrahouse/terraform-aws-openvpn
#   CI_SA_ID              account_id of the CI service account. Default: openvpn-tester
#   WIF_GITHUB_POOL       pool id. Default: github
#   WIF_GITHUB_PROVIDER   provider id. Default: github-oidc
#   CI_GRANT_TEST_ROLES   grant the roles test_google_wif needs. Default: true
#                         (set false if CI only runs test_module, which needs the
#                         provider to configure but creates no google resources).

set -euo pipefail

PROJECT="${GOOGLE_PROJECT:-openvpn-427715}"
REPO="${GITHUB_REPO:-infrahouse/terraform-aws-openvpn}"
SA_ID="${CI_SA_ID:-openvpn-tester}"
POOL="${WIF_GITHUB_POOL:-github}"
PROVIDER="${WIF_GITHUB_PROVIDER:-github-oidc}"
GRANT_TEST_ROLES="${CI_GRANT_TEST_ROLES:-true}"

SA="${SA_ID}@${PROJECT}.iam.gserviceaccount.com"

# Read the active account from local config first -- this makes NO API call, so
# it cannot trigger a reauth prompt, which lets us warn about the prompt BEFORE
# the first API call below hits it.
ACTIVE_ACCOUNT="$(gcloud config get-value account 2>/dev/null || true)"

echo "Project:         $PROJECT"
echo "Repo:            $REPO"
echo "Service account: $SA"
echo "Signed in as:    ${ACTIVE_ACCOUNT:-<unknown -- run: gcloud auth list>}"
echo
echo "HEADS UP: gcloud may now prompt 'Please enter your password:'. That is a"
echo "  Google *reauthentication* for ${ACTIVE_ACCOUNT:-your gcloud account} -- enter"
echo "  THAT Google account's password. Not a new password, nothing to do with AWS"
echo "  or GitHub. (If it does, gcloud only asks once per session.)"
echo

# First API call -- may trigger the reauth prompt warned about above.
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
echo "Project number:  $PROJECT_NUMBER"
echo

echo "==> Enabling required APIs..."
# cloudresourcemanager is needed by the terraform google provider to read/manage
# google_project_service (the destroy phase fails without it).
gcloud services enable \
  iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project="$PROJECT"

echo "==> Service account..."
if gcloud iam service-accounts describe "$SA" --project="$PROJECT" >/dev/null 2>&1; then
  echo "    exists"
else
  gcloud iam service-accounts create "$SA_ID" \
    --project="$PROJECT" \
    --display-name="GitHub Actions CI (terraform-aws-openvpn)"
fi

echo "==> Workload identity pool..."
if gcloud iam workload-identity-pools describe "$POOL" \
  --project="$PROJECT" --location=global >/dev/null 2>&1; then
  echo "    exists"
else
  gcloud iam workload-identity-pools create "$POOL" \
    --project="$PROJECT" --location=global \
    --display-name="GitHub Actions"
fi

echo "==> GitHub OIDC provider (locked to $REPO)..."
if gcloud iam workload-identity-pools providers describe "$PROVIDER" \
  --project="$PROJECT" --location=global --workload-identity-pool="$POOL" >/dev/null 2>&1; then
  echo "    exists"
else
  # attribute-condition is mandatory on OIDC providers and locks federation to
  # this one repository -- no other repo's GitHub token can mint credentials.
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" \
    --project="$PROJECT" --location=global --workload-identity-pool="$POOL" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
    --attribute-condition="assertion.repository=='${REPO}'"
fi

echo "==> Letting $REPO impersonate the service account..."
MEMBER="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL}/attribute.repository/${REPO}"
gcloud iam service-accounts add-iam-policy-binding "$SA" \
  --project="$PROJECT" \
  --role="roles/iam.workloadIdentityUser" \
  --member="$MEMBER" >/dev/null

if [ "$GRANT_TEST_ROLES" = "true" ]; then
  echo "==> Granting the roles the test needs..."
  # serviceAccountKeyAdmin: the test lists the SA's keys to assert it is keyless;
  # serviceAccountAdmin does NOT include iam.serviceAccountKeys.list.
  for role in \
    roles/iam.serviceAccountAdmin \
    roles/iam.serviceAccountKeyAdmin \
    roles/iam.workloadIdentityPoolAdmin \
    roles/serviceusage.serviceUsageAdmin; do
    gcloud projects add-iam-policy-binding "$PROJECT" \
      --member="serviceAccount:${SA}" \
      --role="$role" \
      --condition=None >/dev/null
    echo "    $role"
  done
else
  echo "==> Skipping test_google_wif roles (CI_GRANT_TEST_ROLES=false)"
fi

echo
echo "Done. Add these to the 'Configure GCP Credentials' step in terraform-CI.yml:"
echo
echo "  workload_identity_provider: projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL}/providers/${PROVIDER}"
echo "  service_account:            ${SA}"
