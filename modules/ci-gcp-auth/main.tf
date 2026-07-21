# ============================================================================
# CI GCP auth (Terraform equivalent of scripts/setup-ci-gcp-auth.sh)
# ----------------------------------------------------------------------------
# One-time bootstrap so a GitHub Actions runner can authenticate to GCP
# keylessly (GitHub OIDC -> Workload Identity Federation), letting Terraform
# create the openvpn module's google resources in CI. Apply it once yourself
# with GCP owner/IAM-admin credentials (gcloud ADC) -- the runner cannot create
# this before it can authenticate.
#
# It creates: the CI runner service account, a GitHub OIDC pool + provider
# (locked to var.github_repo), the impersonation binding, and the project roles
# the runner needs. No service-account key is ever created.
#
# NOTE: this pool is SEPARATE from the AWS pool the openvpn module creates; this
# one federates GitHub, that one federates the EC2 instance role.
# ============================================================================

data "google_project" "this" {
  project_id = var.project
}

resource "google_project_service" "required" {
  for_each = toset([
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    # cloudresourcemanager is needed by the provider to manage google_project_service
    # (the openvpn module's API enablement) -- its absence breaks the CI destroy.
    "cloudresourcemanager.googleapis.com",
  ])

  project            = var.project
  service            = each.value
  disable_on_destroy = false
}

resource "google_service_account" "ci" {
  project      = var.project
  account_id   = var.service_account_id
  display_name = "GitHub Actions CI (terraform-aws-openvpn)"

  depends_on = [google_project_service.required]
}

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project
  workload_identity_pool_id = var.pool_id
  display_name              = "GitHub Actions"

  depends_on = [google_project_service.required]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  # checkov:skip=CKV_GCP_125:Federation is locked to one repository via
  # attribute_condition (assertion.repository == '<repo>') -- the pattern
  # google-github-actions itself recommends. CKV_GCP_125 only recognizes a
  # condition that pins assertion.sub, which varies by ref/environment and is a
  # weaker lock than pinning the repository.
  project                            = var.project
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = "GitHub Actions OIDC"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }

  # Lock federation to this one repository -- no other repo's GitHub token can
  # mint credentials for this pool.
  attribute_condition = "assertion.repository == '${var.github_repo}'"
}

# Let the repository's GitHub Actions impersonate the CI service account.
resource "google_service_account_iam_member" "impersonate" {
  service_account_id = google_service_account.ci.name
  role               = "roles/iam.workloadIdentityUser"
  member = format(
    "principalSet://iam.googleapis.com/%s/attribute.repository/%s",
    google_iam_workload_identity_pool.github.name,
    var.github_repo,
  )
}

# Project roles the runner needs to create the openvpn module's google resources
# and run its integration test:
#   serviceAccountAdmin       - create the directory-reader SA and its IAM
#   serviceAccountKeyAdmin    - the test lists SA keys to assert it is keyless
#   workloadIdentityPoolAdmin - create the module's AWS pool + provider
#   serviceUsageAdmin         - enable the required APIs
resource "google_project_iam_member" "ci" {
  # checkov:skip=CKV_GCP_49:The CI runner must CREATE the openvpn module's
  # directory-reader SA (serviceAccountAdmin) and list its keys to assert it is
  # keyless (serviceAccountKeyAdmin). Those are project-level because the target
  # SA does not exist yet, so they cannot be scoped to a single resource. This is
  # a dedicated CI project; the identical grants are made by the bash equivalent.
  for_each = toset([
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountKeyAdmin",
    "roles/iam.workloadIdentityPoolAdmin",
    "roles/serviceusage.serviceUsageAdmin",
  ])

  project = var.project
  role    = each.value
  member  = "serviceAccount:${google_service_account.ci.email}"
}
