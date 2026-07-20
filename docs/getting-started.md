# Getting Started

This guide walks through deploying the OpenVPN module for the first time.

## Prerequisites

- **Terraform** `~> 1.5`
- **AWS provider** `>= 5.11, < 7.0`
- An existing **VPC** with:
    - **Private (backend) subnets** for the OpenVPN instances and portal tasks
    - **Public (load balancer) subnets** for the Network Load Balancer
- A **Route 53 hosted zone** for the domain you will serve the VPN and portal from
- An **IAM role ARN** that is allowed to update the Google OAuth secret in Secrets Manager
- A second AWS **region** for cross-region replication of the portal access-log bucket
  (must differ from the deploy region)

## Provider configuration

The module requires two AWS provider configurations: the default `aws` provider for resources, and
an `aws.dns` aliased provider for Route 53 records. They can point at the same account/region, or
`aws.dns` can target the account that owns the hosted zone.

```hcl
provider "aws" {
  region = "us-west-2"
}

# DNS provider — same account here, but can target a different DNS account.
provider "aws" {
  alias  = "dns"
  region = "us-west-2"
}
```

## Minimal deployment

```hcl
data "aws_route53_zone" "this" {
  name = "example.com"
}

module "openvpn" {
  source  = "registry.infrahouse.com/infrahouse/openvpn/aws"
  version = "6.1.0"
  providers = {
    aws     = aws
    aws.dns = aws.dns
  }

  environment                = "production"
  alarm_emails               = ["alerts@example.com"]
  backend_subnet_ids         = var.private_subnet_ids
  lb_subnet_ids              = var.public_subnet_ids
  zone_id                    = data.aws_route53_zone.this.zone_id
  google_oauth_client_writer = data.aws_iam_role.admin.arn
  replication_region         = "us-east-1"
}
```

Apply it:

```bash
terraform init
terraform plan
terraform apply
```

## Google OAuth setup

The module creates a **placeholder secret** for the Google OAuth credentials. The portal cannot
authenticate users until you populate it:

1. Create an **OAuth 2.0 Client ID** in the Google Cloud Console.
2. Add the authorized JavaScript origin: `https://openvpn-portal.<your-domain>`
3. Add the authorized redirect URI:
   `https://openvpn-portal.<your-domain>/login/google/authorized`
4. Download the client secret JSON.
5. Update the AWS secret (name is exposed via the `google_client_secret` output) using `ih-secrets`
   or the AWS CLI.
6. The portal detects the updated secret and enables authentication.

For multiple Google Workspace domains, mark the OAuth app **External** in the Google Cloud Console
and list the extra domains in [`allowed_domains`](configuration.md#authentication). The domain from
`zone_id` is always included automatically.

## Connecting

1. Browse to `https://openvpn-portal.<your-domain>`.
2. Sign in with a Google account from an allowed domain.
3. Download the generated `.ovpn` profile.
4. Import it into your OpenVPN client and connect.

## Next steps

- Review every input in the [Configuration](configuration.md) reference.
- See [Examples](examples.md) for multi-domain, custom-routes, and scaling setups.
- Keep [Troubleshooting](troubleshooting.md) handy for first-connection issues.
