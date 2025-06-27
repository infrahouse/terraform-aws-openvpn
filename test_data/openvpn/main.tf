module "openvpn" {
  source = "../../"
  providers = {
    aws     = aws
    aws.dns = aws
  }
  backend_subnet_ids           = var.backend_subnet_ids
  lb_subnet_ids                = var.lb_subnet_ids
  zone_id                      = data.aws_route53_zone.test-zone.zone_id
  asg_min_size                 = 1
  asg_max_size                 = 1
  portal-image                 = "${data.aws_caller_identity.this.account_id}.dkr.ecr.${var.region}.amazonaws.com/portal:latest"
  google_oauth_client_writer   = tolist(data.aws_iam_roles.sso-admin.arns)[0]
  alb_access_log_force_destroy = true
  portal_workers_count         = 1
  portal_instance_type         = "t3a.nano"
  routes = [
    {
      network : cidrhost(data.aws_vpc.mgmt.cidr_block, 0)
      netmask : cidrnetmask(data.aws_vpc.mgmt.cidr_block)
    }
  ]
}
