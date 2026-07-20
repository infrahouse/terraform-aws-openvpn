data "aws_caller_identity" "this" {}
data "aws_region" "current" {}

data "aws_route53_zone" "test-zone" {
  name = var.test_zone
}

data "aws_iam_roles" "sso-admin" {
  name_regex  = "AWSReservedSSO_AWSAdministratorAccess_.*"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

# Unique per-environment suffix so a destroy+recreate never collides with a
# pool/SA that GCP has only soft-deleted (ids are reserved ~30 days). Held in
# state, so repeated applies in the same state reuse it (no needless churn).
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

locals {
  suffix = random_string.suffix.result
}

# Throwaway SSH keypair for debugging the test instances. The private key is
# written to env/id_rsa (env/ is gitignored, so it never lands in the repo).
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "test" {
  key_name   = "openvpn-wif-${local.suffix}"
  public_key = tls_private_key.ssh.public_key_openssh
}

# local_sensitive_file (not local_file) keeps the key out of plan/apply output.
resource "local_sensitive_file" "ssh_private_key" {
  content         = tls_private_key.ssh.private_key_openssh
  filename        = "${path.module}/env/id_rsa"
  file_permission = "0600"

  # ssh(1) refuses a key whose directory is group/world-writable.
  directory_permission = "0700"
}

module "openvpn" {
  source = "../../"
  providers = {
    aws     = aws
    aws.dns = aws
  }
  alarm_emails = [
    "test@example.com"
  ]
  backend_subnet_ids = var.backend_subnet_ids
  lb_subnet_ids      = var.lb_subnet_ids
  zone_id            = data.aws_route53_zone.test-zone.zone_id
  asg_min_size       = 1
  asg_max_size       = 1
  instance_type      = "t3a.small" # Use smaller instance type for tests
  key_pair_name      = aws_key_pair.test.key_name
  # The portal image is never pulled in this test -- we only assert the GCP
  # side. A placeholder URL keeps apply cheap (no docker build/push).
  portal-image                 = "${data.aws_caller_identity.this.account_id}.dkr.ecr.${var.region}.amazonaws.com/portal:latest"
  google_oauth_client_writer   = tolist(data.aws_iam_roles.sso-admin.arns)[0]
  alb_access_log_force_destroy = true
  # CRR replica must differ from the deploy region; flip to us-west-2 if the test runs in us-east-1
  replication_region   = var.region == "us-east-1" ? "us-west-2" : "us-east-1"
  portal_workers_count = 1
  allowed_domains = [
    "infrahouse.com",
    "tinyfish.io",
  ]

  # Feature under test: keyless Google Workspace directory revocation.
  enable_google_directory_revocation = true
  google_directory_admin_subject     = var.google_directory_admin_subject
  google_wif_pool_id                 = "ovpn-wif-${local.suffix}"
  google_wif_provider_id             = "aws-ovpn-${local.suffix}"
  google_directory_reader_sa_id      = "ovpn-dir-${local.suffix}"
}
