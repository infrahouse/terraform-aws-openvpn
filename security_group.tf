resource "aws_security_group" "openvpn" {
  vpc_id      = data.aws_subnet.selected.vpc_id
  name_prefix = "openvpn"
  description = "Manage traffic to openvpn"
  tags = merge({
    Name : "openvpn"
    },
    local.default_module_tags
  )
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  description       = "Allow SSH traffic"
  security_group_id = aws_security_group.openvpn.id
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = data.aws_vpc.selected.cidr_block
  tags = merge({
    Name = "SSH access"
    },
    local.default_module_tags
  )
}

resource "aws_vpc_security_group_ingress_rule" "openvpn" {
  description       = "Allow NLB health checks"
  security_group_id = aws_security_group.openvpn.id
  from_port         = local.openvpn_tcp_port
  to_port           = local.openvpn_tcp_port
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  tags = merge(
    {
      Name = "OpenVPN access"
    },
    local.default_module_tags
  )
}

resource "aws_vpc_security_group_ingress_rule" "icmp" {
  description       = "Allow all ICMP traffic"
  security_group_id = aws_security_group.openvpn.id
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

resource "aws_vpc_security_group_egress_rule" "default" {
  description       = "Allow all traffic"
  security_group_id = aws_security_group.openvpn.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  tags = merge(
    {
      Name = "outgoing traffic"
    },
    local.default_module_tags
  )
}
