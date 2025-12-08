# Security group for OpenVPN Auto Scaling Group instances (private)
# Note: Resource name kept as "openvpn" for backward compatibility
# Renaming would cause instance replacement in production
resource "aws_security_group" "openvpn" {
  vpc_id      = data.aws_subnet.selected.vpc_id
  name_prefix = "openvpn"
  description = "Manage traffic to openvpn" # Keep the description to not re-created the security group

  tags = merge(
    {
      Name = "openvpn-asg"
    },
    local.default_module_tags
  )
}

# Allow all traffic from NLB (health checks + forwarded VPN connections)
resource "aws_vpc_security_group_ingress_rule" "asg_from_nlb" {
  description                  = "Allow all traffic from NLB (health checks and forwarded VPN connections)"
  security_group_id            = aws_security_group.openvpn.id
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.nlb.id

  tags = merge(
    {
      Name = "Traffic from NLB"
    },
    local.default_module_tags
  )
}

# Allow all traffic within ASG (inter-instance communication)
resource "aws_vpc_security_group_ingress_rule" "asg_self" {
  description                  = "Allow all traffic between ASG instances (inter-instance communication)"
  security_group_id            = aws_security_group.openvpn.id
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.openvpn.id

  tags = merge(
    {
      Name = "Inter-instance traffic"
    },
    local.default_module_tags
  )
}

# Allow SSH from VPC (admin access)
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  description       = "Allow SSH from VPC (administrative access)"
  security_group_id = aws_security_group.openvpn.id
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = data.aws_vpc.selected.cidr_block

  tags = merge(
    {
      Name = "SSH access"
    },
    local.default_module_tags
  )
}

# Allow ICMP from VPC (diagnostics and Path MTU Discovery)
resource "aws_vpc_security_group_ingress_rule" "icmp" {
  description       = "Allow ICMP from VPC (for diagnostics and Path MTU Discovery)"
  security_group_id = aws_security_group.openvpn.id
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

# Allow all outbound traffic
resource "aws_vpc_security_group_egress_rule" "default" {
  description       = "Allow all outbound traffic from ASG instances"
  security_group_id = aws_security_group.openvpn.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(
    {
      Name = "All outbound traffic"
    },
    local.default_module_tags
  )
}
