terraform {
  required_version = "~> 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
      configuration_aliases = [
        aws.dns # AWS provider for DNS
      ]

    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    # Used only when enable_google_directory_revocation = true. When the feature
    # is off, no google resources exist, so the consumer's `provider "google"`
    # block may be empty and uncredentialed -- it is never configured.
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}
