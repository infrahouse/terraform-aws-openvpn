output "google_client_secret" {
  value = module.openvpn.google_client_secret
}

output "account_id" {
  value = data.aws_caller_identity.this.account_id
}

output "portal_url" {
  description = "URL of the OpenVPN portal web interface"
  value       = module.openvpn.portal_url
}

output "autoscaling_group_name" {
  description = "Name of the autoscaling group managing the OpenVPN instances"
  value       = module.openvpn.autoscaling_group_name
}
