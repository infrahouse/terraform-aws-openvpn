locals {
  name_prefix = substr("openvpn", 0, 6)
}

resource "aws_lb" "openvpn" {
  name_prefix                      = local.name_prefix
  load_balancer_type               = "network"
  subnets                          = var.lb_subnet_ids
  enable_cross_zone_load_balancing = true
  security_groups = [
    aws_security_group.nlb.id
  ]
  tags = merge(
    local.default_module_tags,
    {
      module_version : local.module_version
    }
  )
}

resource "aws_lb_target_group" "openvpn" {
  name_prefix = local.name_prefix
  port        = local.openvpn_tcp_port
  protocol    = "TCP"
  vpc_id      = data.aws_vpc.selected.id
  tags = merge(
    {
      Name = "${var.service_name}-target-group"
    },
    local.default_module_tags
  )
  stickiness {
    enabled = true
    type    = "source_ip"
  }
  health_check {
    protocol = "TCP"
    port     = local.openvpn_tcp_port
  }
}

resource "aws_lb_listener" "openvpn" {
  load_balancer_arn = aws_lb.openvpn.arn
  port              = local.openvpn_tcp_port
  protocol          = "TCP"
  tags = merge(
    {
      Name = "${var.service_name}-listener"
    },
    local.default_module_tags
  )
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.openvpn.arn
  }
}
