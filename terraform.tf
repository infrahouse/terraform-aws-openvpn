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
    # Only used when var.enable_google_directory_revocation = true. The root
    # module must configure a `google` provider (project + region + auth) when
    # the feature is on; when off, no google resources are created and the
    # provider is never contacted.
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}
