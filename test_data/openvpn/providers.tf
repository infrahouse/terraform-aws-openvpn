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

# Required by the openvpn module even with the WIF feature off. Empty and
# uncredentialed on purpose: enable_google_directory_revocation defaults to
# false, so no google resource exists and this provider is never configured.
provider "google" {}
