resource "random_string" "role-suffix" {
  length  = 6
  special = false
}

locals {
  module_version = "4.5.0"

  default_module_tags = {
    environment : var.environment
    service : var.service_name
    account : data.aws_caller_identity.current.account_id
    created_by_module : "infrahouse/openvpn/aws"

  }
  openvpn_tcp_port     = 1194
  key_pair_name        = var.key_pair_name == null ? aws_key_pair.deployer.key_name : var.key_pair_name
  canonical_owner_id   = "099720109477"
  ami_name_pattern_pro = "ubuntu-pro-server/images/hvm-ssd-gp3/ubuntu-${var.ubuntu_codename}-*"
}
