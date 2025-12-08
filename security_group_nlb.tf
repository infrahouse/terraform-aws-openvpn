# Security group for Network Load Balancer (public-facing)
resource "aws_security_group" "nlb" {
  vpc_id      = data.aws_subnet.selected.vpc_id
  name_prefix = "openvpn-nlb-"
  description = "Security group for OpenVPN Network Load Balancer (public-facing)"

  tags = merge(
    {
      Name = "openvpn-nlb"
    },
    local.default_module_tags
  )
}

# Allow OpenVPN client connections from internet
resource "aws_vpc_security_group_ingress_rule" "nlb_openvpn" {
  description       = "Allow OpenVPN client connections from internet"
  security_group_id = aws_security_group.nlb.id
  from_port         = local.openvpn_tcp_port
  to_port           = local.openvpn_tcp_port
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(
    {
      Name = "OpenVPN client access"
    },
    local.default_module_tags
  )
}

# Allow ICMP from internet (for troubleshooting, MTU discovery)
resource "aws_vpc_security_group_ingress_rule" "nlb_icmp" {
  description       = "Allow ICMP from internet (for troubleshooting and Path MTU Discovery)"
  security_group_id = aws_security_group.nlb.id
  from_port         = -1
  to_port           = -1
  ip_protocol       = "icmp"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(
    {
      Name = "ICMP traffic"
    },
    local.default_module_tags
  )
}

# Allow all outbound traffic
resource "aws_vpc_security_group_egress_rule" "nlb" {
  description       = "Allow all outbound traffic from NLB"
  security_group_id = aws_security_group.nlb.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(
    {
      Name = "All outbound traffic"
    },
    local.default_module_tags
  )
}