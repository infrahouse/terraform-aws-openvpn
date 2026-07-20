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

# The WIF feature is on in this test, so the google provider must be configured.
# Authenticates via ADC (gcloud locally, google-github-actions/auth in CI).
provider "google" {
  project = var.google_project
}
