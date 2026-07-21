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
    # The module always manages GCP resources (keyless directory revocation), so
    # a configured google provider is always required. See the README "Google
    # Configuration" section for credentials (laptop / CI).
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}
