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

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Log Group for OpenVPN server logs"
  value       = module.openvpn.cloudwatch_log_group_name
}

# --- Google WIF outputs (consumed by tests/wif_helpers.py) ---
output "google_directory_reader_sa_email" {
  value = module.openvpn.google_directory_reader_sa_email
}

output "google_directory_reader_client_id" {
  value = module.openvpn.google_directory_reader_client_id
}

output "google_wif_credential_config_json" {
  value = module.openvpn.google_wif_credential_config_json
}

output "wif_pool_id" {
  value = "ovpn-wif-${random_string.suffix.result}"
}

output "wif_provider_id" {
  value = "aws-ovpn-${random_string.suffix.result}"
}

output "wif_sa_id" {
  value = "ovpn-dir-${random_string.suffix.result}"
}
