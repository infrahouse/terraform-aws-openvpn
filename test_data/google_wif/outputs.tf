output "account_id" {
  value = data.aws_caller_identity.this.account_id
}

output "google_project" {
  value = var.google_project
}

output "autoscaling_group_name" {
  value = module.openvpn.autoscaling_group_name
}

output "ssh_private_key_path" {
  description = "Path to the generated private key for SSH-ing to the test instances."
  value       = local_sensitive_file.ssh_private_key.filename
}

output "wif_pool_id" {
  value = "ovpn-wif-${local.suffix}"
}

output "wif_provider_id" {
  value = "aws-ovpn-${local.suffix}"
}

output "wif_sa_id" {
  value = "ovpn-dir-${local.suffix}"
}

output "google_directory_reader_sa_email" {
  value = module.openvpn.google_directory_reader_sa_email
}

output "google_directory_reader_client_id" {
  value = module.openvpn.google_directory_reader_client_id
}

output "google_wif_credential_config_json" {
  value = module.openvpn.google_wif_credential_config_json
}
