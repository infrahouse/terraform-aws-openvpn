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
# This is unconditional: the module always requires a `google` provider and
# always creates these resources. See the "Google Configuration" section of the
# README for provider credentials (laptop / CI) and the manual DWD step.
# ============================================================================

locals {
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

  wif_principal = format(
    "principalSet://iam.googleapis.com/%s/attribute.aws_role/%s",
    google_iam_workload_identity_pool.openvpn.name,
    local.instance_assumed_role_arn,
  )

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
  wif_credential_config = jsonencode({
    universe_domain    = "googleapis.com"
    type               = "external_account"
    audience           = "//iam.googleapis.com/${google_iam_workload_identity_pool_provider.aws.name}"
    subject_token_type = "urn:ietf:params:aws:token-type:aws4_request"
    token_url          = "https://sts.googleapis.com/v1/token"
    credential_source = {
      environment_id                 = "aws1"
      region_url                     = "http://169.254.169.254/latest/meta-data/placement/availability-zone"
      url                            = "http://169.254.169.254/latest/meta-data/iam/security-credentials"
      regional_cred_verification_url = "https://sts.{region}.amazonaws.com?Action=GetCallerIdentity&Version=2011-06-15"
      imdsv2_session_token_url       = "http://169.254.169.254/latest/api/token"
    }
  })

  # One admin subject per Workspace tenant. WIF_ADMIN_SUBJECTS (comma-joined) is
  # authoritative for the toolkit (>= 2.62.0); WIF_ADMIN_SUBJECT stays as the
  # first element so an older reader still works (first tenant only).
  wif_admin_subjects = var.google_workspace_admin_emails

  wif_env_file = templatefile("${path.module}/templates/wif.env.tftpl", {
    credential_path   = local.wif_credential_path
    sa_email          = google_service_account.dir_reader.email
    sa_client_id      = google_service_account.dir_reader.unique_id
    expected_role_arn = local.instance_assumed_role_arn
    admin_subject     = local.wif_admin_subjects[0]
    admin_subjects    = join(",", local.wif_admin_subjects)
  })

  # Files the instance needs to use the federation, plus the self-verifying
  # diagnostic. Appended to the userdata module's extra_files in asg.tf.
  wif_extra_files = [
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
  ]
}

resource "google_project_service" "revocation" {
  for_each = toset([
    "sts.googleapis.com",
    "iamcredentials.googleapis.com",
    "iam.googleapis.com",
    "admin.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}

# The directory-reader SA. No google_service_account_key is ever created -- that
# is the whole point.
resource "google_service_account" "dir_reader" {
  account_id   = var.google_directory_reader_sa_id
  display_name = "OpenVPN directory reader"
  description  = "Keyless (WIF) SA; reads Workspace user suspension status to revoke VPN certs"

  depends_on = [google_project_service.revocation]
}

resource "google_iam_workload_identity_pool" "openvpn" {
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
  workload_identity_pool_id          = google_iam_workload_identity_pool.openvpn.workload_identity_pool_id
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
  service_account_id = google_service_account.dir_reader.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.wif_principal
}

resource "google_service_account_iam_member" "wif_token_creator" {
  service_account_id = google_service_account.dir_reader.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = local.wif_principal
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
variable "google_workspace_admin_emails" {
  description = <<-EOT
    Google Workspace admin emails the VPN impersonates to read who has been
    deactivated (the domain-wide-delegation "subjects"). Provide ONE per Google
    Workspace tenant whose users you allow to connect -- e.g. separate tenants
    behind the same VPN each need their own admin here. Each must be a real,
    active admin in its own Workspace, and the directory-reader SA's client ID
    (output google_directory_reader_client_id) must be authorized for scope
    admin.directory.user.readonly in EACH of those Workspaces' Admin consoles.
    A non-existent address fails at runtime with
    `invalid_grant: Invalid email or User ID`. One tenant = a one-element list.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.google_workspace_admin_emails) > 0
    error_message = "Provide at least one Workspace admin email."
  }
  validation {
    condition     = alltrue([for e in var.google_workspace_admin_emails : length(trimspace(e)) > 0])
    error_message = "Workspace admin emails must not be blank."
  }
  validation {
    condition     = length(var.google_workspace_admin_emails) == length(distinct(var.google_workspace_admin_emails))
    error_message = "Workspace admin emails must be unique."
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
  description = "Email of the keyless directory-reader service account."
  value       = google_service_account.dir_reader.email
}

output "google_directory_reader_client_id" {
  description = <<-EOT
    Numeric OAuth2 client ID of the directory-reader SA. Paste this into the
    Workspace Admin console (https://admin.google.com/ac/owl/domainwidedelegation)
    together with scope https://www.googleapis.com/auth/admin.directory.user.readonly.
    This is the one step Terraform cannot perform; verify-wif.sh prints it on the
    instance too.
  EOT
  value       = google_service_account.dir_reader.unique_id
}

output "google_wif_credential_config_json" {
  description = <<-EOT
    Keyless external-account credential config written to the instance. Contains
    no secret (only IDs + IMDS URLs).
  EOT
  value       = local.wif_credential_config
}
