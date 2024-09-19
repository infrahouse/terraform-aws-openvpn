resource "random_string" "role-suffix" {
  length  = 6
  special = false
}

locals {
  default_module_tags = {
    environment : var.environment
    service : var.service_name
    account : data.aws_caller_identity.current.account_id
    created_by_module : "infrahouse/openvpn/aws"

  }
  ec2_role_name            = "${var.service_name}-${random_string.role-suffix.result}"
  ec2_role_arn             = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.ec2_role_name}"
  lifecycle_hook_wait_time = 300
  openvpn_tcp_port         = 1194
  key_pair_name            = var.key_pair_name == null ? aws_key_pair.deployer.key_name : var.key_pair_name

}
