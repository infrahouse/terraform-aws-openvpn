provider "aws" {
  region = var.region
  dynamic "assume_role" {
    for_each = var.role_arn != null ? [1] : []
    content {
      role_arn = var.role_arn
    }
  }
  default_tags {
    tags = {
      "created_by" : "infrahouse/terraform-aws-openvpn" # GitHub repository that created a resource
    }
  }
}

# Authenticates via Application Default Credentials (ADC) so the same config
# works both locally (`gcloud auth application-default login`) and in GitHub
# Actions (google-github-actions/auth). No key material lives in the repo.
provider "google" {
  project = var.google_project
}
