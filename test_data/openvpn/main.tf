resource "aws_key_pair" "black-mbp" {
  public_key = file("${path.module}/files/mediapc.pub")
}

# Unique per-run suffix for the WIF pool/provider/SA ids, held in state so a
# destroy+recreate never collides with GCP's ~30-day soft-deleted ids.
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

module "openvpn" {
  source = "../../"
  providers = {
    aws     = aws
    aws.dns = aws
    google  = google
  }
  alarm_emails = [
    "test@example.com"
  ]
  backend_subnet_ids           = var.backend_subnet_ids
  lb_subnet_ids                = var.lb_subnet_ids
  zone_id                      = data.aws_route53_zone.test-zone.zone_id
  asg_min_size                 = 1
  asg_max_size                 = 1
  instance_type                = "t3a.small" # Use smaller instance type for tests
  portal-image                 = "${data.aws_caller_identity.this.account_id}.dkr.ecr.${var.region}.amazonaws.com/portal:latest"
  google_oauth_client_writer   = tolist(data.aws_iam_roles.sso-admin.arns)[0]
  alb_access_log_force_destroy = true
  # CRR replica must differ from the deploy region; flip to us-west-2 if the test runs in us-east-1
  replication_region   = var.region == "us-east-1" ? "us-west-2" : "us-east-1"
  portal_workers_count = 1
  key_pair_name        = aws_key_pair.black-mbp.key_name
  allowed_domains = [
    "infrahouse.com",
    "example.com",
  ]
  routes = [
    {
      network : cidrhost(data.aws_vpc.mgmt.cidr_block, 0)
      netmask : cidrnetmask(data.aws_vpc.mgmt.cidr_block)
    }
  ]

  # Keyless Google Workspace directory revocation (always on).
  google_workspace_admin_emails = var.google_workspace_admin_emails
  google_wif_pool_id            = "ovpn-wif-${random_string.suffix.result}"
  google_wif_provider_id        = "aws-ovpn-${random_string.suffix.result}"
  google_directory_reader_sa_id = "ovpn-dir-${random_string.suffix.result}"
}
