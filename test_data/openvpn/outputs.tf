output "google_client_secret" {
  value = module.openvpn.google_client_secret
}

output "account_id" {
  value = data.aws_caller_identity.this.account_id
}
