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
