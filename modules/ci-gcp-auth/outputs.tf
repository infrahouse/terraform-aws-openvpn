output "workload_identity_provider" {
  description = "Full provider resource name for google-github-actions/auth's workload_identity_provider input."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "service_account" {
  description = "CI runner service account email for google-github-actions/auth's service_account input."
  value       = google_service_account.ci.email
}

output "github_actions_auth_step" {
  description = <<-EOT
    A ready-to-paste GitHub Actions step. Add it to BOTH the plan and apply
    workflows (each job needs `permissions: id-token: write`).
  EOT
  value       = <<-EOT
    - name: Configure GCP Credentials
      uses: google-github-actions/auth@v2
      with:
        workload_identity_provider: ${google_iam_workload_identity_pool_provider.github.name}
        service_account: ${google_service_account.ci.email}
  EOT
}
