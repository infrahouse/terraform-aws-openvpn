resource "aws_security_group" "efs" {
  description = "Security group for EFS volume"
  name_prefix = "openvpn-efs-"
  vpc_id      = data.aws_subnet.selected.vpc_id

  tags = merge(
    {
      Name : "OpenVPN config"
    },
    local.default_module_tags
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
    local.default_module_tags
  )
}

resource "aws_vpc_security_group_ingress_rule" "efs_icmp" {
  description       = "Allow ICMP traffic from VPC (for Path MTU Discovery and network diagnostics)"
  security_group_id = aws_security_group.efs.id
  from_port         = -1
  to_port           = -1
  ip_protocol       = "icmp"
  cidr_ipv4         = data.aws_vpc.selected.cidr_block
  tags = merge(
    {
      Name = "ICMP traffic"
    },
    local.default_module_tags
  )
}

#tfsec:ignore:aws-vpc-no-public-egress-sgr
resource "aws_vpc_security_group_egress_rule" "efs" {
  description       = "Allow all outbound traffic from EFS (EFS-initiated connections for metadata and management)"
  security_group_id = aws_security_group.efs.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  tags = merge(
    {
      Name = "EFS outgoing traffic"
    },
    local.default_module_tags
  )
}
