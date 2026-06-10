# terraform-aws-openvpn

Terraform module that deploys a production-ready **OpenVPN server on AWS** with Google OAuth 2.0
authentication and a web portal for self-service profile management.

Users authenticate with their Google account, download their OpenVPN profile from the portal, and
connect to reach private resources inside your VPC — no manual certificate handling required.

## Features

- **OpenVPN server** in an Auto Scaling group behind a Network Load Balancer
- **Google OAuth authentication** with multi-domain support (4.0.0+)
- **Self-service portal** (ECS service) for downloading per-user VPN profiles
- **EFS-backed configuration** (encrypted) shared across all OpenVPN instances
- **Automated EFS backups** via AWS Backup (365-day retention by default)
- **CloudWatch** metrics, logs, and CPU alarms
- **Cross-region replication** of portal ALB access logs for ISO 27001 / Vanta compliance
- **Route 53 integration** for DNS records

## Quick Start

```hcl
module "openvpn" {
  source  = "registry.infrahouse.com/infrahouse/openvpn/aws"
  version = "5.3.0"
  providers = {
    aws     = aws
    aws.dns = aws
  }

  environment                = "production"
  alarm_emails               = ["alerts@example.com"]
  backend_subnet_ids         = var.private_subnet_ids
  lb_subnet_ids              = var.public_subnet_ids
  zone_id                    = data.aws_route53_zone.this.zone_id
  google_oauth_client_writer = data.aws_iam_role.admin.arn

  # Cross-region replication target for the portal ALB access-log bucket.
  # Must differ from the region this module is deployed in.
  replication_region = "us-east-1"
}
```

After the first apply, finish the [Google OAuth setup](getting-started.md#google-oauth-setup) so the
portal can authenticate users.

## Documentation

- [Getting Started](getting-started.md) — prerequisites and first deployment
- [Architecture](architecture.md) — how the pieces fit together
- [Configuration](configuration.md) — every input variable explained
- [Examples](examples.md) — common deployment patterns
- [Troubleshooting](troubleshooting.md) — diagnosing common issues
- [Changelog](changelog.md) — release history
