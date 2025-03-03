output "google_client_secret" {
  description = "google_client secret name. OpenVPN portal admin must update the secret with a Google OAuth client JSON."
  value       = module.google_client.secret_name
}

output "load_balancer_arn" {
  description = "ARN of the load balancer for the OpenVPN portal"
  value       = module.openvpn-portal.load_balancer_arn
}
