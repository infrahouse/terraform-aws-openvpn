# ci-gcp-auth

Terraform equivalent of [`scripts/setup-ci-gcp-auth.sh`](../../scripts/setup-ci-gcp-auth.sh):
one-time bootstrap so a GitHub Actions runner can authenticate to GCP
**keylessly** (GitHub OIDC → Workload Identity Federation) and let Terraform
create the openvpn module's google resources in CI.

Apply it **once yourself** with GCP owner/IAM-admin credentials (`gcloud auth
application-default login`) — the runner can't create this before it can
authenticate. It creates the CI runner service account, a GitHub OIDC pool +
provider locked to your repository, the impersonation binding, and the project
roles the runner needs. **No service-account key is created.**

> This pool is separate from the one the openvpn module creates: this federates
> GitHub, that federates the EC2 instance role.

## Usage

```hcl
provider "google" {
  project = "your-gcp-project"
}

module "ci_gcp_auth" {
  source      = "registry.infrahouse.com/infrahouse/openvpn/aws//modules/ci-gcp-auth"
  project     = "your-gcp-project"
  github_repo = "your-org/your-terraform-repo"
}

output "github_actions_auth_step" {
  value = module.ci_gcp_auth.github_actions_auth_step
}
```

```shell
gcloud auth application-default login
terraform init && terraform apply
```

The `github_actions_auth_step` output is a ready-to-paste step for **both** your
plan and apply workflows (each job needs `permissions: id-token: write`):

```yaml
- name: Configure GCP Credentials
  uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: projects/NNN/locations/global/workloadIdentityPools/github/providers/github-oidc
    service_account: openvpn-tester@your-gcp-project.iam.gserviceaccount.com
```
