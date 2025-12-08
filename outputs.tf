output "google_client_secret" {
  description = "Google OAuth client secret name. The OpenVPN portal admin must update the secret with a Google OAuth client JSON."
  value       = module.google_client.secret_name
}

output "load_balancer_arn" {
  description = "ARN of the load balancer for the OpenVPN portal"
  value       = module.openvpn-portal.load_balancer_arn
}

output "autoscaling_group_name" {
  description = "Name of the autoscaling group managing the OpenVPN instances"
  value       = aws_autoscaling_group.openvpn.name
}

output "openvpn-instance-role-arn" {
  description = "ARN of the IAM role attached to the OpenVPN instance"
  value       = module.instance_profile.instance_role_arn
}

output "portal_url" {
  description = "URL of the OpenVPN portal web interface"
  value       = "https://${module.openvpn-portal.dns_hostnames[0]}"
}

output "vpn_server_fqdn" {
  description = "Fully qualified domain name (FQDN) of the OpenVPN server endpoint for client connections"
  value       = aws_route53_record.vpn_cname.fqdn
}

output "security_group_id" {
  description = "ID of the security group attached to OpenVPN Auto Scaling Group instances"
  value       = aws_security_group.openvpn.id
}

output "nlb_security_group_id" {
  description = "ID of the security group attached to the Network Load Balancer"
  value       = aws_security_group.nlb.id
}

output "efs_security_group_id" {
  description = "ID of the security group attached to the EFS file system for OpenVPN configuration storage"
  value       = aws_security_group.efs.id
}

output "efs_file_system_id" {
  description = "ID of the EFS file system used for storing OpenVPN configuration and certificates"
  value       = aws_efs_file_system.openvpn-config-enc.id
}

output "efs_dns_name" {
  description = "DNS name of the EFS file system mount target for accessing shared OpenVPN configuration"
  value       = aws_efs_file_system.openvpn-config-enc.dns_name
}

output "nlb_dns_name" {
  description = "DNS name of the Network Load Balancer serving OpenVPN traffic"
  value       = aws_lb.openvpn.dns_name
}

output "nlb_arn" {
  description = "ARN of the Network Load Balancer"
  value       = aws_lb.openvpn.arn
}

output "openvpn_port" {
  description = "TCP port number used by OpenVPN server for client connections"
  value       = local.openvpn_tcp_port
}

output "target_group_arn" {
  description = "ARN of the Network Load Balancer target group for OpenVPN instances"
  value       = aws_lb_target_group.openvpn.arn
}

output "launch_template_id" {
  description = "ID of the EC2 launch template used by the OpenVPN Auto Scaling Group"
  value       = aws_launch_template.openvpn.id
}

output "launch_template_latest_version" {
  description = "Latest version number of the OpenVPN launch template"
  value       = aws_launch_template.openvpn.latest_version
}
