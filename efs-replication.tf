resource "aws_efs_replication_configuration" "openvpn-config" {
  source_file_system_id = aws_efs_file_system.openvpn-config.id
  destination {
    file_system_id = aws_efs_file_system.openvpn-config-enc.id
  }
}
