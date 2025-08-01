resource "aws_efs_file_system" "openvpn-config-enc" {
  creation_token = "${var.service_name}-config-encrypted"
  encrypted      = true
  kms_key_id     = data.aws_kms_key.efs_default.arn

  tags = merge(
    {
      Name = "${var.service_name}-config-encrypted"
    },
    local.default_module_tags
  )
}

resource "aws_efs_mount_target" "openvpn-config-enc" {
  for_each       = toset(var.backend_subnet_ids)
  file_system_id = aws_efs_file_system.openvpn-config-enc.id
  subnet_id      = each.key
  security_groups = [
    aws_security_group.efs.id
  ]
  lifecycle {
    create_before_destroy = false
  }
}
