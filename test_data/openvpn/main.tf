resource "aws_key_pair" "black-mbp" {
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDBVMh/uBvxKF88z0VxbFYJwhGJklVWf90HJOiESQetC8AJXx6M0x9faPiK5z/SsFjNerCU9TwUZzEgLudB3OWm/X8BChGH3r1g5MsP3FpCd2UCQGu5/0jdX60TePhQ+4SVuoYpjaKIKhulzKM+lEcsJHIk+pM+cKA9yCt4rWghgp7OLXAJE2cA0qy0vv/DytReHoEPFFFtrKUSltmQhu1ggGXH+5pb7kFx2GWLElhVAeG0d+mJdRUXXnDzqjGvW2IrmOAcKJXkF5m9ITjKn55UiuZIPx4k/iLMQQ+am2F/VlttAdEl8Tgo27Q5UhqAH08sHrVnr1qciS8Rdavt8rNPSseFVh7e3wVvMBH4NvEd2gVPThssxlC7BjIfLQGb1jFiRdMHagbG4U4vtpr2pus2PnmcMOQwdC3WjvmyXHjCRQiS16FwJburRfBKGhQf30wjyzvyJ3PDMk4Sni/3Gl69TKb2s91Zq56yhCCrUjMhTtqjmdNvD8jEmIswV+fTyoU= aleks@Black-MBP"
}

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
  key_pair_name                = aws_key_pair.black-mbp.key_name
  allowed_domains = [
    "infrahouse.com",
    "tinyfish.io",
  ]
  routes = [
    {
      network : cidrhost(data.aws_vpc.mgmt.cidr_block, 0)
      netmask : cidrnetmask(data.aws_vpc.mgmt.cidr_block)
    }
  ]
}
