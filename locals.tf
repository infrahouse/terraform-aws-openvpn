resource "random_string" "role-suffix" {
  length  = 6
  special = false
}

locals {
  module_version = "5.2.0"

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

  # Portal ECS task count defaults
  # Default min: one task per backend subnet for HA across AZs
  # Default max: min + 1 to allow for rolling updates
  portal_task_min_count = var.portal_task_min_count != null ? var.portal_task_min_count : length(var.backend_subnet_ids)
  portal_task_max_count = var.portal_task_max_count != null ? var.portal_task_max_count : local.portal_task_min_count + 1

  # Autoscaling network bandwidth target calculation
  # Uses AWS ec2_instance_type data source to get baseline bandwidth in Gbps
  # Applied to MAX(NetworkIn, NetworkOut) to scale when either direction is saturated
  # Formula: (baseline_gbps * 1000 to get Mbps * percentage / 100) * 1000000 to get bytes/sec
  # Example: c6in.large (25 Gbps) @ 60% = 15,000,000,000 bytes/sec
  autoscaling_target_network = (
    tolist(data.aws_ec2_instance_type.openvpn.network_cards)[0].baseline_bandwidth * 1000
    * var.autoscaling_target_network_percentage / 100
  ) * 1000000
}
