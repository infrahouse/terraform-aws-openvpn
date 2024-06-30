resource "aws_route53_record" "vpn_cname" {
  provider = aws.dns
  name     = "${var.service_name}.${data.aws_route53_zone.current.name}"
  type     = "CNAME"
  zone_id  = data.aws_route53_zone.current.zone_id
  ttl      = 300
  records = [
    aws_lb.openvpn.dns_name
  ]
}
