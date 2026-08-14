# Basic Example

The minimum configuration required to deploy an OpenVPN server with Google
OAuth authentication using the terraform-aws-openvpn module.

## What This Example Creates

- VPC with public subnets (load balancer) and private subnets behind NAT
  gateways (OpenVPN instances)
- Route53 hosted zone
- Network Load Balancer for OpenVPN client traffic
- Auto Scaling group of OpenVPN instances
- OpenVPN Portal (ECS service) for Google OAuth login and profile download
- Encrypted EFS file system for shared OpenVPN configuration
- GCP Workload Identity Federation resources for keyless certificate
  revocation of suspended Google Workspace users
- CloudWatch alarms with email notifications

## Prerequisites

- AWS CLI configured with appropriate credentials
- A GCP project and Application Default Credentials
  (`gcloud auth application-default login`)
- Terraform ~> 1.5

## Usage

```bash
terraform init
terraform plan
terraform apply
```

After the apply, complete the Google OAuth setup: create an OAuth 2.0 Client ID
in the Google Cloud Console and store its JSON in the secret from the
`google_client_secret` output. The full walkthrough is in
[Getting started](https://infrahouse.github.io/terraform-aws-openvpn/getting-started/).

Then users open the portal, sign in with Google, and download their profile:

```bash
open "https://$(terraform output -raw portal_url)"
```

## Outputs

| Name | Description |
|------|-------------|
| vpn_server_fqdn | Hostname VPN clients connect to |
| portal_url | OpenVPN portal where users download their VPN profile |
| google_client_secret | Secrets Manager secret to update with the Google OAuth client JSON |
| autoscaling_group_name | Auto Scaling group running the OpenVPN instances |

## Notes

- The Route53 zone created in this example uses `example.com`. Replace it with
  your actual domain (typically via a `data "aws_route53_zone"` lookup instead).
- `google_workspace_admin_emails` must list a real Workspace admin for each
  Google Workspace tenant whose users connect to the VPN.
- After the first apply, authorize domain-wide delegation once in each
  Workspace admin console — `sudo /opt/openvpn-wif/verify-wif.sh` on an
  instance prints the exact Client ID and scope to paste.
- The example looks up an AWS SSO administrator role for
  `google_oauth_client_writer`. Replace the lookup if your admin role is
  named differently.
