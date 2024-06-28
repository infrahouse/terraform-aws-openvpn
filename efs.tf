resource "aws_efs_file_system" "openvpn-config" {
  creation_token = "openvpn-config"
  tags = merge(
    {
      Name = "openvpn-config"
    },
    local.tags
  )
}

resource "aws_efs_mount_target" "openvpn-config" {
  for_each       = toset(var.backend_subnet_ids)
  file_system_id = aws_efs_file_system.openvpn-config.id
  subnet_id      = each.key
  security_groups = [
    aws_security_group.efs.id
  ]
  lifecycle {
    create_before_destroy = false
  }
}

resource "aws_security_group" "efs" {
  description = "Security group for EFS volume"
  name_prefix = "openvpn-efs-"
  vpc_id      = data.aws_subnet.selected.vpc_id

  tags = merge(
    {
      Name : "OpenVPN config"
    },
    local.tags
  )
}

resource "aws_vpc_security_group_ingress_rule" "efs" {
  description       = "Allow NFS traffic to EFS volume"
  security_group_id = aws_security_group.efs.id
  from_port         = 2049
  to_port           = 2049
  ip_protocol       = "tcp"
  cidr_ipv4         = data.aws_vpc.selected.cidr_block
  tags = merge({
    Name = "NFS traffic"
    },
    local.tags
  )
}

resource "aws_vpc_security_group_ingress_rule" "efs_icmp" {
  description       = "Allow all ICMP traffic"
  security_group_id = aws_security_group.efs.id
  from_port         = -1
  to_port           = -1
  ip_protocol       = "icmp"
  cidr_ipv4         = "0.0.0.0/0"
  tags = merge(
    {
      Name = "ICMP traffic"
    },
    local.tags
  )
}

resource "aws_vpc_security_group_egress_rule" "efs" {
  security_group_id = aws_security_group.efs.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  tags = merge(
    {
      Name = "EFS outgoing traffic"
    },
    local.tags
  )
}
