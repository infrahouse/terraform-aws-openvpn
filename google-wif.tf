# ============================================================================
# Google Workload Identity Federation for deactivated-user cert revocation
# ----------------------------------------------------------------------------
# Stands up, entirely in Terraform, the GCP side that lets the OpenVPN EC2
# instance role ask the Workspace Directory API "who is suspended?" WITHOUT a
# service-account key at rest. Replaces the manual gcloud/console steps.
#
# Chain: EC2 instance role -> GCP STS (federation) -> signJwt on the SA
#        (Google signs the domain-wide-delegation assertion) -> a token that
#        acts as a Workspace admin -> Directory API.
#
# The ONE thing Terraform cannot do (no resource exists in hashicorp/google):
#   authorize this SA's client ID for the directory scope in the Workspace
#   Admin console (https://admin.google.com/ac/owl/domainwidedelegation).
#   The client ID + scope to paste are emitted as outputs below, and
#   verify-wif.sh prints them on the instance.
#
# Everything here is gated on var.enable_google_directory_revocation (default
# false). When false, no GCP resources are created. Consumers must still declare
# a `google` provider block, but it can be empty and uncredentialed -- with the
# feature off nothing references it, so it is never configured or contacted.
# ============================================================================

locals {
  google_revocation_enabled = var.enable_google_directory_revocation
  gcount                    = local.google_revocation_enabled ? 1 : 0

  # module.instance_profile.instance_role_arn is arn:aws:iam::ACCT:role[/path]/NAME.
  # STS presents the caller as arn:aws:sts::ACCT:assumed-role/NAME/SESSION, and
  # the provider's attribute-mapping (below) normalizes that to
  # arn:aws:sts::ACCT:assumed-role/NAME. Rebuild that normalized ARN here so the
  # attribute-condition and the principalSet binding match exactly.
  instance_role_name = reverse(split("/", module.instance_profile.instance_role_arn))[0]
  instance_assumed_role_arn = format(
    "arn:aws:sts::%s:assumed-role/%s",
    data.aws_caller_identity.current.account_id,
    local.instance_role_name,
  )

  wif_principal = local.google_revocation_enabled ? format(
    "principalSet://iam.googleapis.com/%s/attribute.aws_role/%s",
    google_iam_workload_identity_pool.openvpn[0].name,
    local.instance_assumed_role_arn,
  ) : null

  # Everything lives under /opt/openvpn-wif, NOT /etc/openvpn: the OpenVPN role
  # (Puppet + the openvpn package) actively manages /etc/openvpn and reaps files
  # it does not declare, which silently deleted wif.env when it lived there.
  wif_dir             = "/opt/openvpn-wif"
  wif_credential_path = "${local.wif_dir}/google-wif.json"

  # The keyless credential-configuration the instance points
  # GOOGLE_APPLICATION_CREDENTIALS at. Contains NO secret -- only IDs and the
  # AWS IMDS URLs. Equivalent to `gcloud iam workload-identity-pools
  # create-cred-config ... --aws --enable-imdsv2`. {region} is a literal
  # placeholder the google-auth library substitutes at runtime.
  wif_credential_config = local.google_revocation_enabled ? jsonencode({
    universe_domain    = "googleapis.com"
    type               = "external_account"
    audience           = "//iam.googleapis.com/${google_iam_workload_identity_pool_provider.aws[0].name}"
    subject_token_type = "urn:ietf:params:aws:token-type:aws4_request"
    token_url          = "https://sts.googleapis.com/v1/token"
    credential_source = {
      environment_id                 = "aws1"
      region_url                     = "http://169.254.169.254/latest/meta-data/placement/availability-zone"
      url                            = "http://169.254.169.254/latest/meta-data/iam/security-credentials"
      regional_cred_verification_url = "https://sts.{region}.amazonaws.com?Action=GetCallerIdentity&Version=2011-06-15"
      imdsv2_session_token_url       = "http://169.254.169.254/latest/api/token"
    }
  }) : null

  wif_env_file = local.google_revocation_enabled ? templatefile("${path.module}/templates/wif.env.tftpl", {
    credential_path   = local.wif_credential_path
    sa_email          = google_service_account.dir_reader[0].email
    sa_client_id      = google_service_account.dir_reader[0].unique_id
    expected_role_arn = local.instance_assumed_role_arn
    admin_subject     = var.google_workspace_admin_email == null ? "" : var.google_workspace_admin_email
  }) : ""

  # Files the instance needs to use the federation, plus the self-verifying
  # diagnostic. Wired into cloud-init via extra_files in asg.tf; empty when the
  # feature is disabled so no google outputs are referenced.
  wif_extra_files = local.google_revocation_enabled ? [
    {
      path        = local.wif_credential_path
      permissions = "0644"
      content     = local.wif_credential_config
    },
    {
      path        = "${local.wif_dir}/wif.env"
      permissions = "0644"
      content     = local.wif_env_file
    },
    {
      path        = "${local.wif_dir}/verify-wif.sh"
      permissions = "0755"
      content     = file("${path.module}/scripts/verify-wif.sh")
    },
  ] : []
}

resource "google_project_service" "revocation" {
  for_each = local.google_revocation_enabled ? toset([
    "sts.googleapis.com",
    "iamcredentials.googleapis.com",
    "iam.googleapis.com",
    "admin.googleapis.com",
  ]) : toset([])

  service            = each.value
  disable_on_destroy = false
}

# The directory-reader SA. No google_service_account_key is ever created -- that
# is the whole point.
resource "google_service_account" "dir_reader" {
  count = local.gcount

  account_id   = var.google_directory_reader_sa_id
  display_name = "OpenVPN directory reader"
  description  = "Keyless (WIF) SA; reads Workspace user suspension status to revoke VPN certs"

  depends_on = [google_project_service.revocation]
}

resource "google_iam_workload_identity_pool" "openvpn" {
  count = local.gcount

  workload_identity_pool_id = var.google_wif_pool_id
  display_name              = "OpenVPN AWS federation"
  description               = "Federates the OpenVPN EC2 instance role into GCP (no keys)"

  depends_on = [google_project_service.revocation]
}

resource "google_iam_workload_identity_pool_provider" "aws" {
  # checkov:skip=CKV_GCP_125:This is an AWS provider, not a GitHub Actions OIDC trust policy. The check
  # reads conf["oidc"][0] before testing the issuer, so it raises TypeError on any non-OIDC provider and
  # its broad except returns FAILED -- contradicting its own "if it's not OIDC ... then pass" branch.
  # Federation here is locked down by attribute_condition below (pinned to one assumed-role ARN).
  count = local.gcount

  workload_identity_pool_id          = google_iam_workload_identity_pool.openvpn[0].workload_identity_pool_id
  workload_identity_pool_provider_id = var.google_wif_provider_id
  display_name                       = "AWS OpenVPN"

  aws {
    account_id = data.aws_caller_identity.current.account_id
  }

  # Normalize AWS's assumed-role/NAME/SESSION arn down to a stable
  # assumed-role/NAME so the binding matches regardless of session name.
  attribute_mapping = {
    "google.subject" = "assertion.arn"
    "attribute.aws_role" = join("", [
      "assertion.arn.contains('assumed-role') ? ",
      "assertion.arn.extract('{account_arn}assumed-role/') + 'assumed-role/' + ",
      "assertion.arn.extract('assumed-role/{role_name}/') : assertion.arn",
    ])
  }

  # Lock federation to this one instance role -- nothing else in the AWS
  # account can mint a token for this pool.
  attribute_condition = "attribute.aws_role == '${local.instance_assumed_role_arn}'"
}

# workloadIdentityUser lets the instance role impersonate the SA;
# serviceAccountTokenCreator is what makes signJwt (the DWD assertion) work.
# Both are required.
resource "google_service_account_iam_member" "wif_impersonate" {
  count = local.gcount

  service_account_id = google_service_account.dir_reader[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.wif_principal
}

resource "google_service_account_iam_member" "wif_token_creator" {
  count = local.gcount

  service_account_id = google_service_account.dir_reader[0].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = local.wif_principal
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
variable "enable_google_directory_revocation" {
  description = <<-EOT
    Enable the Google Workspace integration that lets the OpenVPN instance
    revoke certificates for deactivated (suspended/deleted) directory users,
    keylessly via Workload Identity Federation.

    When true, the root module MUST configure a `google` provider (project +
    credentials, e.g. ADC) and set `google_workspace_admin_email`. When false
    (default), no GCP resources are created; a `google` provider block must
    still be declared but may be empty and uncredentialed -- nothing references
    it, so it is never configured.
  EOT
  type        = bool
  default     = false
}

variable "google_workspace_admin_email" {
  description = <<-EOT
    Email of a Google Workspace admin the VPN impersonates to read who has been
    deactivated (the domain-wide-delegation "subject"). Must be a real, active
    Workspace user with permission to read the directory -- a non-existent
    address fails at runtime with `invalid_grant: Invalid email or User ID`.

    Required when enable_google_directory_revocation = true.
  EOT
  type        = string
  default     = null

  validation {
    condition = !var.enable_google_directory_revocation || (
      var.google_workspace_admin_email != null && var.google_workspace_admin_email != ""
    )
    error_message = "google_workspace_admin_email must be set when enable_google_directory_revocation is true."
  }
}

variable "google_wif_pool_id" {
  description = "Workload Identity Pool ID for the OpenVPN AWS federation."
  type        = string
  default     = "openvpn-wif-pool"
}

variable "google_wif_provider_id" {
  description = "Workload Identity Pool *provider* ID for the AWS provider."
  type        = string
  default     = "aws-openvpn"
}

variable "google_directory_reader_sa_id" {
  description = "account_id (local part) of the keyless directory-reader service account."
  type        = string
  default     = "openvpn-dir-reader"
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
output "google_directory_reader_sa_email" {
  description = "Email of the keyless directory-reader service account (null when the feature is disabled)."
  value       = one(google_service_account.dir_reader[*].email)
}

output "google_directory_reader_client_id" {
  description = <<-EOT
    Numeric OAuth2 client ID of the directory-reader SA. Paste this into the
    Workspace Admin console (https://admin.google.com/ac/owl/domainwidedelegation)
    together with scope https://www.googleapis.com/auth/admin.directory.user.readonly.
    This is the one step Terraform cannot perform; verify-wif.sh prints it on the
    instance too. Null when the feature is disabled.
  EOT
  value       = one(google_service_account.dir_reader[*].unique_id)
}

output "google_wif_credential_config_json" {
  description = <<-EOT
    Keyless external-account credential config written to the instance. Contains
    no secret (only IDs + IMDS URLs). Null when the feature is disabled.
  EOT
  value       = local.wif_credential_config
}
