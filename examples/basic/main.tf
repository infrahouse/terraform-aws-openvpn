# Basic Example
# The minimum configuration required to deploy an OpenVPN server
# with Google OAuth authentication.

terraform {
  required_version = "~> 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

# The module requires an aliased AWS provider for DNS. When the Route53 zone
# lives in the same account, alias the same provider configuration.
provider "aws" {
  alias  = "dns"
  region = "us-west-2"
}

# The module always manages GCP resources for keyless Google Workspace
# directory revocation, so a google provider is required.
# Authenticate via Application Default Credentials (`gcloud auth application-default login`).
provider "google" {
  project = "my-gcp-project" # replace with your GCP project ID
}

locals {
  environment = "development"
}

# Create a VPC with public subnets for the load balancer and
# private subnets (behind a NAT gateway) for the OpenVPN instances.
module "network" {
  source  = "registry.infrahouse.com/infrahouse/service-network/aws"
  version = "5.0.2"

  environment           = local.environment
  service_name          = "openvpn"
  vpc_cidr_block        = "10.1.0.0/16"
  management_cidr_block = "10.1.0.0/16"
  replication_region    = "us-east-1"
  subnets = [
    {
      cidr                    = "10.1.0.0/24"
      availability_zone       = "us-west-2a"
      map_public_ip_on_launch = true
      create_nat              = true
    },
    {
      cidr                    = "10.1.1.0/24"
      availability_zone       = "us-west-2b"
      map_public_ip_on_launch = true
      create_nat              = true
    },
    {
      cidr              = "10.1.2.0/24"
      availability_zone = "us-west-2a"
      forward_to        = "10.1.0.0/24"
    },
    {
      cidr              = "10.1.3.0/24"
      availability_zone = "us-west-2b"
      forward_to        = "10.1.1.0/24"
    }
  ]
}

# Create a Route53 zone (or look up an existing one with a data source)
resource "aws_route53_zone" "example" {
  name = "example.com"
}

# IAM role that is allowed to update the Google OAuth client secret
# after the initial deployment (e.g. your admin/SSO role).
data "aws_iam_roles" "admin" {
  name_regex  = "AWSAdministratorAccess.*"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

module "openvpn" {
  source  = "registry.infrahouse.com/infrahouse/openvpn/aws"
  version = "10.0.0"

  providers = {
    aws     = aws
    aws.dns = aws.dns
    google  = google
  }

  environment        = local.environment
  backend_subnet_ids = module.network.subnet_private_ids
  lb_subnet_ids      = module.network.subnet_public_ids
  zone_id            = aws_route53_zone.example.zone_id

  # IAM role ARN that can update the Google OAuth client secret.
  google_oauth_client_writer = tolist(data.aws_iam_roles.admin.arns)[0]

  # One Google Workspace admin email per Workspace tenant. Suspended users
  # are discovered through this admin and their VPN certificates revoked.
  google_workspace_admin_emails = ["admin@example.com"]

  # Each address receives an SNS subscription confirmation email that
  # must be confirmed before alarm notifications are delivered.
  alarm_emails = ["ops-team@example.com"]

  # Region for cross-region replication of access logs.
  # Must differ from the deployment region.
  replication_region = "us-east-1"

  # Give VPN clients access to the VPC CIDR.
  routes = [
    {
      network = "10.1.0.0"
      netmask = "255.255.0.0"
    }
  ]
}

output "vpn_server_fqdn" {
  description = "Hostname VPN clients connect to"
  value       = module.openvpn.vpn_server_fqdn
}

output "portal_url" {
  description = "OpenVPN portal where users download their VPN profile"
  value       = module.openvpn.portal_url
}

output "google_client_secret" {
  description = "Secrets Manager secret to update with the Google OAuth client JSON"
  value       = module.openvpn.google_client_secret
}

output "autoscaling_group_name" {
  description = "Auto Scaling group running the OpenVPN instances"
  value       = module.openvpn.autoscaling_group_name
}
