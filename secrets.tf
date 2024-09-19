resource "random_password" "ca_passkey" {
  length = 31
}
module "ca_passkey" {
  source             = "registry.infrahouse.com/infrahouse/secret/aws"
  version            = "0.5.0"
  secret_description = "OpenVPN CA Key Passphrase"
  secret_name_prefix = "openvpn_ca_passphrase"
  secret_value       = random_password.ca_passkey.result
  tags               = local.default_module_tags
  readers = [
    module.instance_profile.instance_role_arn
  ]
}


resource "random_password" "flask_secret_key" {
  special = false
  length  = 31
}
module "flask_secret_key" {
  source             = "registry.infrahouse.com/infrahouse/secret/aws"
  version            = "0.5.0"
  secret_description = "Flask secret key"
  secret_name_prefix = "flask_secret_key"
  secret_value       = random_password.flask_secret_key.result
  tags               = local.default_module_tags
  readers = [
    aws_iam_role.openvpn_portal_role.arn
  ]
}

module "google_client" {
  source             = "infrahouse/secret/aws"
  version            = "0.5.0"
  secret_description = "A JSON with Google OAuth Client ID"
  secret_name_prefix = "google_client"
  tags               = local.default_module_tags
  readers = [
    aws_iam_role.openvpn_portal_role.arn
  ]
  writers = [
    var.google_oauth_client_writer
  ]
}
