variable "project" {
  description = "GCP project ID that the openvpn module deploys into (the same one CI targets)."
  type        = string
}

variable "github_repo" {
  description = <<-EOT
    org/repo whose GitHub Actions are allowed to federate into GCP (e.g.
    my-org/my-terraform-repo). Federation is locked to exactly this repository.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[^/[:space:]]+/[^/[:space:]]+$", var.github_repo))
    error_message = "github_repo must be in org/repo form, e.g. my-org/my-repo. Got: ${var.github_repo}"
  }
}

variable "service_account_id" {
  description = "account_id (local part) of the CI runner service account Terraform impersonates in CI."
  type        = string
  default     = "openvpn-tester"
}

variable "pool_id" {
  description = "Workload Identity Pool ID for the GitHub OIDC federation."
  type        = string
  default     = "github"
}

variable "provider_id" {
  description = "Workload Identity Pool *provider* ID for GitHub's OIDC issuer."
  type        = string
  default     = "github-oidc"
}
