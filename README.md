# terraform-aws-openvpn

The [openvpn module](https://registry.terraform.io/modules/infrahouse/openvpn/aws/latest) deploys 
an OpenVPN server with Google OAuth 2.0 authentication.

Starting with version 4.0.0, the module supports VPN users from multiple Google domains.

![OpenVPN diagram](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/openvpn.drawio.png)

The OpenVPN Portal is a web application that authenticates users via their Google accounts 
and generates an OpenVPN profile for them.

You should place the OpenVPN server in public subnets in your AWS environment 
so authorized users can access resources in private subnets.

## Quick start

```hcl
module "vpn" {
  source  = "registry.infrahouse.com/infrahouse/openvpn/aws"
  version = "7.0.0"

  providers = {
    aws     = aws
    aws.dns = aws
    google  = google
  }

  backend_subnet_ids         = module.management.subnet_private_ids
  lb_subnet_ids              = module.management.subnet_public_ids
  google_oauth_client_writer = tolist(data.aws_iam_roles.sso-admin.arns)[0]
  zone_id                    = module.infrahouse_com.infrahouse_zone_id
  google_workspace_admin_email = "admin@infrahouse.com"
}
```

The module needs a `google` provider in addition to `aws` — see
[Google configuration](#google-configuration). For the full walkthrough (create
the PR, wire up OAuth, install the client, connect), see
**[Getting started](https://infrahouse.github.io/terraform-aws-openvpn/getting-started/)**.

## Documentation

Full documentation lives at
**[infrahouse.github.io/terraform-aws-openvpn](https://infrahouse.github.io/terraform-aws-openvpn/)**:

- [Getting started](https://infrahouse.github.io/terraform-aws-openvpn/getting-started/) — step-by-step deployment.
- [Architecture](https://infrahouse.github.io/terraform-aws-openvpn/architecture/) — components and how they fit together.
- [Configuration](https://infrahouse.github.io/terraform-aws-openvpn/configuration/) — every input, plus the full **Google configuration** (OAuth, provider credentials, GCP resources, domain-wide delegation, revocation sync).
- [Examples](https://infrahouse.github.io/terraform-aws-openvpn/examples/) — multi-domain, custom routes, scaling.
- [Security](https://infrahouse.github.io/terraform-aws-openvpn/security/) — best practices, logging, and ISO 27001 / SOC compliance.
- [Monitoring & alerts](https://infrahouse.github.io/terraform-aws-openvpn/monitoring/) — CloudWatch alarms and SNS integration.
- [Cost optimization](https://infrahouse.github.io/terraform-aws-openvpn/cost/) — instance sizing and NLB/EFS trade-offs.
- [Troubleshooting](https://infrahouse.github.io/terraform-aws-openvpn/troubleshooting/) — common failures and fixes.

## Google Configuration

The module touches Google in two ways, **both always on** (there is no feature
flag):

- **Portal login (OAuth):** VPN users authenticate with Google to download their
  profile.
- **Directory revocation (keyless Workload Identity Federation):** the OpenVPN
  instance asks Workspace *"which users are suspended?"* and revokes their VPN
  certificates — **with no service-account key at rest**. The trust chain:

  ```
  EC2 instance role -> GCP STS (federation) -> directory-reader service account
                    -> domain-wide delegation (acts as a Workspace admin)
                    -> Directory API
  ```

**Two service accounts are involved — don't confuse them:**

| Service account | Created by | Used by | Purpose |
|-----------------|------------|---------|---------|
| directory-reader (`openvpn-dir-reader`) | **this module** (Terraform) | the OpenVPN instance | read the Workspace directory, keyless via WIF |
| CI runner (your choice of name) | **you**, out of band ([`scripts/setup-ci-gcp-auth.sh`](scripts/setup-ci-gcp-auth.sh)) | GitHub Actions | let Terraform authenticate to GCP in CI |

**Full setup lives in the docs** — the OAuth client, the provider credentials
(laptop / CI), the GCP resources, the one manual domain-wide-delegation step,
verification, and the revocation sync — see
**[Google configuration](https://infrahouse.github.io/terraform-aws-openvpn/configuration/#google-configuration)**
(source: [`docs/configuration.md`](docs/configuration.md)).

In short: declare and pass a `google` provider (it is not auto-inherited through
an explicit `providers` map), set `google_workspace_admin_email` to a real
Workspace admin, `terraform apply`, then authorize domain-wide delegation once in
the Workspace console (`sudo /opt/openvpn-wif/verify-wif.sh` on an instance prints
the exact Client ID + scope to paste).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and how to run the
integration tests.

## License

Apache 2.0 — see [LICENSE](LICENSE).

<!-- BEGIN_TF_DOCS -->

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.5 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 6.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |
| <a name="provider_aws.dns"></a> [aws.dns](#provider\_aws.dns) | ~> 6.0 |
| <a name="provider_google"></a> [google](#provider\_google) | ~> 6.0 |
| <a name="provider_random"></a> [random](#provider\_random) | ~> 3.6 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | ~> 4.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_ca_passkey"></a> [ca\_passkey](#module\_ca\_passkey) | registry.infrahouse.com/infrahouse/secret/aws | 1.1.1 |
| <a name="module_flask_secret_key"></a> [flask\_secret\_key](#module\_flask\_secret\_key) | registry.infrahouse.com/infrahouse/secret/aws | 1.1.1 |
| <a name="module_google_client"></a> [google\_client](#module\_google\_client) | registry.infrahouse.com/infrahouse/secret/aws | 1.1.1 |
| <a name="module_instance_profile"></a> [instance\_profile](#module\_instance\_profile) | registry.infrahouse.com/infrahouse/instance-profile/aws | 1.9.0 |
| <a name="module_openvpn-portal"></a> [openvpn-portal](#module\_openvpn-portal) | registry.infrahouse.com/infrahouse/ecs/aws | 8.1.0 |
| <a name="module_userdata"></a> [userdata](#module\_userdata) | registry.infrahouse.com/infrahouse/cloud-init/aws | 2.4.0 |

## Resources

| Name | Type |
|------|------|
| [aws_autoscaling_group.openvpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group) | resource |
| [aws_autoscaling_policy.cpu_target_tracking](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_policy) | resource |
| [aws_autoscaling_policy.network_target_tracking](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_policy) | resource |
| [aws_backup_plan.efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_plan) | resource |
| [aws_backup_selection.efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_selection) | resource |
| [aws_backup_vault.efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault) | resource |
| [aws_cloudwatch_log_group.openvpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_metric_alarm.cpu_utilization_alarm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_efs_file_system.openvpn-config-enc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_file_system) | resource |
| [aws_efs_mount_target.openvpn-config-enc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_mount_target) | resource |
| [aws_iam_policy.openvpn_portal_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.openvpn_portal_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.backup_efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.backup_restore](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.task_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_key_pair.deployer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/key_pair) | resource |
| [aws_launch_template.openvpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_lb.openvpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.openvpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.openvpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_route53_record.vpn_cname](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_security_group.efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.nlb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.openvpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.nlb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.asg_from_nlb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.asg_self](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.efs_icmp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.icmp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nlb_icmp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nlb_openvpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.ssh](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [google_iam_workload_identity_pool.openvpn](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_workload_identity_pool) | resource |
| [google_iam_workload_identity_pool_provider.aws](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_workload_identity_pool_provider) | resource |
| [google_project_service.revocation](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service) | resource |
| [google_service_account.dir_reader](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account_iam_member.wif_impersonate](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_service_account_iam_member.wif_token_creator](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [random_password.ca_passkey](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.flask_secret_key](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_string.asg_name](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [random_string.profile-suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [random_string.role-suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [tls_private_key.rsa](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [aws_ami.selected](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_ami.ubuntu_pro](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_default_tags.provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/default_tags) | data source |
| [aws_ec2_instance_type.openvpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ec2_instance_type) | data source |
| [aws_iam_policy_document.backup_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.instance_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.openvpn_portal_role_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.openvpn_portal_role_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_kms_key.efs_default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/kms_key) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_route53_zone.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone) | data source |
| [aws_subnet.selected](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |
| [aws_vpc.selected](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alarm_emails"></a> [alarm\_emails](#input\_alarm\_emails) | List of email addresses to receive CloudWatch alarm notifications for the OpenVPN portal ECS service. | `list(string)` | n/a | yes |
| <a name="input_alb_access_log_force_destroy"></a> [alb\_access\_log\_force\_destroy](#input\_alb\_access\_log\_force\_destroy) | Destroy S3 bucket with access logs even if non-empty | `bool` | `false` | no |
| <a name="input_allowed_domains"></a> [allowed\_domains](#input\_allowed\_domains) | List of Google Workspace domains whose users are allowed to connect to the VPN.<br/><br/>The OpenVPN portal uses Google OAuth for authentication. Only users with email<br/>addresses from the specified domains can authenticate and download VPN profiles.<br/><br/>Important notes:<br/>- The domain from zone\_id is AUTOMATICALLY added to this list<br/>- For multi-domain support, your Google OAuth app must be "external" type<br/>- Each domain must be verified in your Google Cloud Console<br/>- Users must have active Google Workspace accounts<br/><br/>Example:<br/>allowed\_domains = [<br/>  "company.com",<br/>  "subsidiary.com"<br/>]<br/><br/>If zone\_id points to example.com, the effective list will be:<br/>["example.com", "company.com", "subsidiary.com"]<br/><br/>Default: [] (only the zone domain is allowed) | `list(string)` | `[]` | no |
| <a name="input_asg_ami"></a> [asg\_ami](#input\_asg\_ami) | Image for EC2 instances | `string` | `null` | no |
| <a name="input_asg_health_check_grace_period"></a> [asg\_health\_check\_grace\_period](#input\_asg\_health\_check\_grace\_period) | Auto Scaling Group health check grace period in seconds.<br/><br/>This is the time AWS waits after instance launch before checking health status.<br/>During this period, instances won't be terminated even if they fail health checks.<br/><br/>Why 600 seconds (10 minutes)?<br/>The OpenVPN server bootstrap process includes:<br/>1. Cloud-init package installation (~2-3 minutes)<br/>2. Puppet run to configure OpenVPN (~3-4 minutes)<br/>3. OpenVPN service startup (~30 seconds)<br/>4. EFS mount and certificate generation (~1-2 minutes)<br/>5. Network Load Balancer health check stabilization (~1 minute)<br/><br/>Typical bootstrap time: 7-8 minutes<br/>Grace period provides 2-3 minute buffer for slower instances or high network latency.<br/><br/>When to increase this value:<br/>- Custom packages in var.packages that take long to install<br/>- Complex Puppet manifests (var.puppet\_manifest)<br/>- Large EFS volumes with many existing certificates<br/>- Regions with slower package mirror speeds<br/><br/>When to decrease this value:<br/>- Using pre-baked AMIs (var.asg\_ami) with packages pre-installed<br/>- Minimal Puppet configuration<br/>- Fast bootstrap observed in testing<br/><br/>Default: 600 seconds (10 minutes) | `number` | `600` | no |
| <a name="input_asg_instance_refresh_max_healthy_percentage"></a> [asg\_instance\_refresh\_max\_healthy\_percentage](#input\_asg\_instance\_refresh\_max\_healthy\_percentage) | Maximum percentage of healthy instances during ASG instance refresh rolling updates.<br/><br/>Controls how many extra instances can be launched during instance refresh:<br/>- 100 = No extra instances (replace one-by-one)<br/>- 110 = Allow 10% extra instances (DEFAULT - enables faster updates)<br/>- 200 = Allow double capacity during refresh<br/><br/>Higher values enable faster updates but temporarily increase costs.<br/>Lower values reduce costs but slow down deployments.<br/><br/>Example with asg\_min\_size=2, asg\_max\_size=4:<br/>- 100%: Replace 1 at a time (max 2 instances total)<br/>- 110%: Can temporarily have 2.2 instances (rounds up to 3)<br/>- 200%: Can temporarily have 4 instances during refresh<br/><br/>Default: 110 (recommended balance of speed and cost) | `number` | `110` | no |
| <a name="input_asg_max_size"></a> [asg\_max\_size](#input\_asg\_max\_size) | Maximum number of instances in ASG | `number` | `null` | no |
| <a name="input_asg_min_size"></a> [asg\_min\_size](#input\_asg\_min\_size) | Minimum number of instances in ASG | `number` | `null` | no |
| <a name="input_autoscaling_target_cpu"></a> [autoscaling\_target\_cpu](#input\_autoscaling\_target\_cpu) | Target CPU utilization percentage for autoscaling. Applied to both OpenVPN ASG and Portal ECS service. | `number` | `60` | no |
| <a name="input_autoscaling_target_network_percentage"></a> [autoscaling\_target\_network\_percentage](#input\_autoscaling\_target\_network\_percentage) | Target network utilization as a percentage of the instance type's baseline bandwidth. Used for OpenVPN ASG network-based autoscaling. | `number` | `60` | no |
| <a name="input_backend_subnet_ids"></a> [backend\_subnet\_ids](#input\_backend\_subnet\_ids) | List of private subnet IDs where OpenVPN server instances and Portal ECS tasks will be deployed.<br/><br/>Requirements:<br/>- Minimum 2 subnets (AWS high availability best practice)<br/>- Must be in different availability zones<br/>- Should have outbound internet access (via NAT Gateway) for package installation<br/>- Used for both OpenVPN EC2 instances and Portal ECS tasks<br/><br/>The number of subnets determines default values for:<br/>- portal\_task\_min\_count (defaults to length of this list)<br/>- asg\_min\_size (defaults to length of this list)<br/><br/>Example: ["subnet-12345678", "subnet-87654321"]<br/><br/>Required. | `list(string)` | n/a | yes |
| <a name="input_cloudinit_extra_commands"></a> [cloudinit\_extra\_commands](#input\_cloudinit\_extra\_commands) | Extra commands for run on ASG. | `list(string)` | `[]` | no |
| <a name="input_cloudwatch_log_retention_days"></a> [cloudwatch\_log\_retention\_days](#input\_cloudwatch\_log\_retention\_days) | Number of days to retain CloudWatch Logs for all services (NLB access logs, ECS logs, etc.) | `number` | `365` | no |
| <a name="input_cloudwatch_namespace"></a> [cloudwatch\_namespace](#input\_cloudwatch\_namespace) | CloudWatch namespace for custom metrics published by the OpenVPN server | `string` | `"OpenVPN/System"` | no |
| <a name="input_efs_backup_retention_days"></a> [efs\_backup\_retention\_days](#input\_efs\_backup\_retention\_days) | Number of days to retain EFS backups. Default: 365 days (matches log retention for compliance). | `number` | `365` | no |
| <a name="input_efs_backup_schedule"></a> [efs\_backup\_schedule](#input\_efs\_backup\_schedule) | Cron expression for EFS backup schedule. Default: daily at 2 AM UTC (cron(0 2 * * ? *)). | `string` | `"cron(0 2 * * ? *)"` | no |
| <a name="input_enable_efs_backup"></a> [enable\_efs\_backup](#input\_enable\_efs\_backup) | Enable AWS Backup for EFS file system containing OpenVPN configuration and certificates. | `bool` | `true` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Name of environment. | `string` | `"development"` | no |
| <a name="input_extra_files"></a> [extra\_files](#input\_extra\_files) | Additional files to create on an instance. | <pre>list(<br/>    object(<br/>      {<br/>        content     = string<br/>        path        = string<br/>        permissions = string<br/>      }<br/>    )<br/>  )</pre> | `[]` | no |
| <a name="input_extra_instance_profile_permissions"></a> [extra\_instance\_profile\_permissions](#input\_extra\_instance\_profile\_permissions) | A JSON with a permissions policy document. The policy will be attached to the ASG instance profile. | `string` | `null` | no |
| <a name="input_extra_policies"></a> [extra\_policies](#input\_extra\_policies) | A map of additional policy ARNs to attach to the jumphost role | `map(string)` | `{}` | no |
| <a name="input_extra_repos"></a> [extra\_repos](#input\_extra\_repos) | Additional APT repositories to configure on an instance. | <pre>map(<br/>    object(<br/>      {<br/>        source    = string<br/>        key       = optional(string)<br/>        keyid     = optional(string)<br/>        keyserver = optional(string)<br/>        machine   = optional(string)<br/>        authFrom  = optional(string)<br/>        priority  = optional(number)<br/>      }<br/>    )<br/>  )</pre> | `{}` | no |
| <a name="input_google_directory_reader_sa_id"></a> [google\_directory\_reader\_sa\_id](#input\_google\_directory\_reader\_sa\_id) | account\_id (local part) of the keyless directory-reader service account. | `string` | `"openvpn-dir-reader"` | no |
| <a name="input_google_oauth_client_writer"></a> [google\_oauth\_client\_writer](#input\_google\_oauth\_client\_writer) | ARN of an IAM role that can update content of google\_oauth\_client secret | `string` | n/a | yes |
| <a name="input_google_wif_pool_id"></a> [google\_wif\_pool\_id](#input\_google\_wif\_pool\_id) | Workload Identity Pool ID for the OpenVPN AWS federation. | `string` | `"openvpn-wif-pool"` | no |
| <a name="input_google_wif_provider_id"></a> [google\_wif\_provider\_id](#input\_google\_wif\_provider\_id) | Workload Identity Pool *provider* ID for the AWS provider. | `string` | `"aws-openvpn"` | no |
| <a name="input_google_workspace_admin_email"></a> [google\_workspace\_admin\_email](#input\_google\_workspace\_admin\_email) | Email of a Google Workspace admin the VPN impersonates to read who has been<br/>deactivated (the domain-wide-delegation "subject"). Must be a real, active<br/>Workspace user with permission to read the directory -- a non-existent<br/>address fails at runtime with `invalid_grant: Invalid email or User ID`. | `string` | n/a | yes |
| <a name="input_gzip_userdata"></a> [gzip\_userdata](#input\_gzip\_userdata) | Whether to gzip compress the cloud-init userdata before base64 encoding.<br/><br/>When true, the userdata is gzip-compressed, significantly reducing its size.<br/>This is important because AWS limits EC2 userdata to 16 KB.<br/><br/>The OpenVPN module's userdata can exceed this limit when extra\_repos includes<br/>embedded GPG keys (~3-6 KB each), multiple SSH users, or extensive custom\_facts.<br/><br/>Default: true (recommended to avoid hitting the 16 KB limit) | `bool` | `true` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 instance type for OpenVPN server instances.<br/><br/>Recommendation: c6in family (compute-optimized, network-optimized)<br/><br/>Why compute-optimized for VPN?<br/>- OpenVPN encryption/decryption is CPU-intensive<br/>- C-series instances provide better performance per dollar for VPN workloads<br/>- Higher single-thread performance benefits VPN connection handling<br/><br/>Recommended instance types:<br/>- c6in.large (DEFAULT): 2 vCPU, 4 GB RAM, 25 Gbps network - Best balance for production<br/>- c6in.xlarge: 4 vCPU, 8 GB RAM, 30 Gbps network - High user count (>100 concurrent)<br/>- c6in.2xlarge: 8 vCPU, 16 GB RAM, 40 Gbps network - Very high throughput needs<br/>- t3a.small: 2 vCPU, 2 GB RAM, 5 Gbps network - Development/testing only<br/><br/>Instance type impacts autoscaling:<br/>- var.autoscaling\_target\_network\_percentage uses the instance's baseline network bandwidth<br/>- Larger instances = higher network bandwidth threshold for autoscaling<br/>- Example: c6in.large (25 Gbps) @ 60% = scales at 15 Gbps<br/>- Example: c6in.xlarge (30 Gbps) @ 60% = scales at 18 Gbps<br/><br/>Cost comparison (us-east-1, on-demand):<br/>- c6in.large: ~$82/month (RECOMMENDED)<br/>- m6in.large: ~$102/month (general-purpose, 19% more expensive)<br/>- t3a.small: ~$15/month (testing only, limited network performance)<br/><br/>Network performance:<br/>- c6in family: 25-200 Gbps (network-optimized)<br/>- m6in family: 25-200 Gbps (network-optimized)<br/>- m7i family: Up to 12.5 Gbps (general-purpose)<br/>- t3/t3a family: Up to 5 Gbps (burstable)<br/><br/>When to use different instance families:<br/>- c6in: Best for production VPN (CPU + network optimized)<br/>- m6in/m7i: If you need more RAM for additional services<br/>- t3/t3a: Development, testing, or very low user count (<10 users)<br/><br/>Default: "c6in.large" | `string` | `"c6in.large"` | no |
| <a name="input_key_pair_name"></a> [key\_pair\_name](#input\_key\_pair\_name) | SSH keypair name for accessing OpenVPN server instances.<br/><br/>⚠️  SECURITY WARNING:<br/>- SSH access should be limited to emergency troubleshooting only<br/>- Use AWS Systems Manager Session Manager for routine access instead<br/>- Restrict security group to allow SSH only from trusted IP ranges<br/>- Consider using short-lived SSH certificates instead of long-lived keys<br/>- Rotate SSH keys regularly<br/>- Monitor SSH access via CloudWatch and VPC Flow Logs<br/><br/>The key pair must exist in AWS before applying this module.<br/><br/>If not specified (null), the module will generate a temporary key pair.<br/>However, for production use, you should provide a managed key pair.<br/><br/>Example: "my-openvpn-emergency-key"<br/><br/>Default: null (module generates a temporary key) | `string` | `null` | no |
| <a name="input_lb_subnet_ids"></a> [lb\_subnet\_ids](#input\_lb\_subnet\_ids) | List of public subnet IDs where the Network Load Balancer will be created.<br/><br/>Requirements:<br/>- Minimum 2 subnets (AWS NLB requirement - must span at least 2 availability zones)<br/>- Must be PUBLIC subnets with internet gateway route<br/>- Must be in different availability zones<br/>- These subnets host the NLB endpoints that VPN clients connect to<br/><br/>The NLB will:<br/>- Accept VPN client connections on TCP port 1194<br/>- Forward traffic to OpenVPN servers in backend\_subnet\_ids<br/>- Have DNS name registered in Route53 zone<br/><br/>Example: ["subnet-public-1", "subnet-public-2"]<br/><br/>Required. | `list(string)` | n/a | yes |
| <a name="input_on_demand_base_capacity"></a> [on\_demand\_base\_capacity](#input\_on\_demand\_base\_capacity) | If specified, the ASG will request spot instances and this will be the minimal number of on-demand instances. | `number` | `null` | no |
| <a name="input_packages"></a> [packages](#input\_packages) | List of packages to install when the instances bootstraps. | `list(string)` | `[]` | no |
| <a name="input_portal-image"></a> [portal-image](#input\_portal-image) | OpenVPN portal docker image | `string` | `"public.ecr.aws/infrahouse/openvpn-portal:latest"` | no |
| <a name="input_portal_instance_type"></a> [portal\_instance\_type](#input\_portal\_instance\_type) | AWS instance type for the OpenVPN portal ECS container instances.<br/><br/>**IMPORTANT:** Must have at least 1 GB of RAM to run the portal container (200 MB)<br/>plus ECS agent, CloudWatch agent, and OS overhead.<br/><br/>Recommended types:<br/>- t3.small / t3a.small (2 GB RAM) - DEFAULT, good for <50 users<br/>- t3.micro / t3a.micro (1 GB RAM) - Minimum viable, tight fit<br/>- t3.medium (4 GB RAM) - High availability setups<br/><br/>⚠️  DO NOT USE: t3.nano, t3a.nano (0.5 GB RAM) - Insufficient memory for ECS task placement<br/><br/>The portal container requires 200 MB memory. After OS (~250 MB), ECS agent (~50 MB),<br/>and CloudWatch agent (~50 MB), a 1 GB instance has ~650 MB available, which is sufficient.<br/>Instances with 512 MB RAM (nano types) only have ~150 MB available after overhead. | `string` | `"t3a.small"` | no |
| <a name="input_portal_task_max_count"></a> [portal\_task\_max\_count](#input\_portal\_task\_max\_count) | Maximum number of ECS tasks for the OpenVPN portal service. Defaults to portal\_task\_min\_count + 1. | `number` | `null` | no |
| <a name="input_portal_task_min_count"></a> [portal\_task\_min\_count](#input\_portal\_task\_min\_count) | Minimum number of ECS tasks for the OpenVPN portal service. Defaults to the number of backend subnets for high availability. | `number` | `null` | no |
| <a name="input_portal_workers_count"></a> [portal\_workers\_count](#input\_portal\_workers\_count) | Number of Unicorn worker processes in the OpenVPN portal web application.<br/><br/>The portal runs as a Flask application served by Unicorn. Each worker process<br/>can handle one request at a time. More workers = more concurrent users.<br/><br/>Recommended worker count by instance type:<br/>- t3.nano / t3a.nano (2 vCPU, 0.5 GB RAM): 2 workers<br/>- t3.small / t3a.small (2 vCPU, 2 GB RAM): 4 workers (DEFAULT)<br/>- t3.medium (2 vCPU, 4 GB RAM): 4-6 workers<br/>- t3.large (2 vCPU, 8 GB RAM): 6-8 workers<br/><br/>Formula: (2 x CPU cores) + 1<br/>Example: t3.small (2 vCPU) = (2 x 2) + 1 = 5 workers (4 is conservative)<br/><br/>Memory per worker: ~150-200 MB<br/>CPU per worker: ~0.5 vCPU under load<br/><br/>When to increase:<br/>- High concurrent user count (>20 simultaneous logins)<br/>- Slow authentication response times<br/>- Using larger instance types (portal\_instance\_type)<br/><br/>When to decrease:<br/>- Very small instance types (t3.nano)<br/>- Low user count (<10 total users)<br/>- Memory pressure in container logs<br/><br/>Note: More workers = more memory usage. Ensure portal\_instance\_type<br/>has sufficient RAM. Monitor ECS task memory utilization in CloudWatch.<br/><br/>Default: 4 (suitable for t3.small with moderate user load) | `number` | `4` | no |
| <a name="input_puppet_custom_facts"></a> [puppet\_custom\_facts](#input\_puppet\_custom\_facts) | A map of custom puppet facts | `any` | `{}` | no |
| <a name="input_puppet_debug_logging"></a> [puppet\_debug\_logging](#input\_puppet\_debug\_logging) | Enable debug logging if true. | `bool` | `false` | no |
| <a name="input_puppet_environmentpath"></a> [puppet\_environmentpath](#input\_puppet\_environmentpath) | A path for directory environments. | `string` | `"{root_directory}/environments"` | no |
| <a name="input_puppet_hiera_config_path"></a> [puppet\_hiera\_config\_path](#input\_puppet\_hiera\_config\_path) | Path to hiera configuration file. | `string` | `"{root_directory}/environments/{environment}/hiera.yaml"` | no |
| <a name="input_puppet_manifest"></a> [puppet\_manifest](#input\_puppet\_manifest) | Path to puppet manifest. By default ih-puppet will apply {root\_directory}/environments/{environment}/manifests/site.pp. | `string` | `null` | no |
| <a name="input_puppet_module_path"></a> [puppet\_module\_path](#input\_puppet\_module\_path) | Path to common puppet modules. | `string` | `"{root_directory}/environments/{environment}/modules:{root_directory}/modules"` | no |
| <a name="input_puppet_root_directory"></a> [puppet\_root\_directory](#input\_puppet\_root\_directory) | Path where the puppet code is hosted. | `string` | `"/opt/puppet-code"` | no |
| <a name="input_replication_region"></a> [replication\_region](#input\_replication\_region) | AWS region for cross-region replication of the OpenVPN portal ALB access-log bucket.<br/>The portal ALB access logs are an audit record under the compliance policy and require<br/>cross-region replication to pass the Vanta aws-s3-cross-region-replication-enabled test.<br/><br/>Must differ from the region this module is deployed in: a same-region replica still fails<br/>the Vanta CRR test. For example, a us-west-1 deployment can replicate to "us-east-1", while<br/>a us-east-1 deployment must pick a different region such as "us-west-2". | `string` | n/a | yes |
| <a name="input_root_volume_size"></a> [root\_volume\_size](#input\_root\_volume\_size) | Root volume size in EC2 instance in Gigabytes | `number` | `30` | no |
| <a name="input_routes"></a> [routes](#input\_routes) | List of network routes to push to VPN clients.<br/><br/>These routes tell VPN clients which traffic should be sent through the VPN tunnel.<br/>Commonly used to route RFC1918 private networks or specific application networks.<br/><br/>Format:<br/>- network: Network address in IPv4 format (e.g., "10.0.0.0")<br/>- netmask: Network mask in IPv4 format (e.g., "255.0.0.0")<br/><br/>Example:<br/>routes = [<br/>  {<br/>    network = "10.0.0.0"<br/>    netmask = "255.0.0.0"<br/>  },<br/>  {<br/>    network = "172.16.0.0"<br/>    netmask = "255.240.0.0"<br/>  }<br/>]<br/><br/>Note: Routes are pushed to clients via OpenVPN configuration.<br/>Clients will route matching traffic through the VPN tunnel.<br/><br/>Default: [] (no custom routes - only VPN subnet routed through tunnel) | <pre>list(<br/>    object(<br/>      {<br/>        network : string,<br/>        netmask : string<br/>      }<br/>    )<br/>  )</pre> | `[]` | no |
| <a name="input_service_name"></a> [service\_name](#input\_service\_name) | Service name used for DNS hostname and resource naming.<br/><br/>This value is used to:<br/>- Create the Route53 DNS record (e.g., openvpn.example.com)<br/>- Name EC2 instances and other AWS resources<br/>- Generate CloudWatch log group names (/aws/openvpn/{environment}/{service\_name})<br/>- Prefix autoscaling policy names<br/><br/>Default: "openvpn" | `string` | `"openvpn"` | no |
| <a name="input_smtp_credentials_secret"></a> [smtp\_credentials\_secret](#input\_smtp\_credentials\_secret) | AWS secret name with SMTP credentials. The secret must contain a JSON with user and password keys. | `string` | `null` | no |
| <a name="input_sns_topic_alarm_arn"></a> [sns\_topic\_alarm\_arn](#input\_sns\_topic\_alarm\_arn) | ARN of SNS topic for Cloudwatch alarms on base EC2 instance. | `string` | `null` | no |
| <a name="input_ubuntu_codename"></a> [ubuntu\_codename](#input\_ubuntu\_codename) | Ubuntu version to use for the OpenVPN server EC2 instance | `string` | `"noble"` | no |
| <a name="input_users"></a> [users](#input\_users) | A list of maps with user definitions according to the cloud-init format | `any` | `null` | no |
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | Route53 hosted zone ID where the OpenVPN service will be accessible.<br/><br/>The module will:<br/>- Create an A record pointing to the Network Load Balancer<br/>- Use the zone's domain name for DNS resolution (e.g., openvpn.example.com)<br/>- Automatically add the zone's domain to allowed\_domains for Google OAuth<br/><br/>Example: "Z1234567890ABC"<br/><br/>Required. Must be a valid Route53 hosted zone ID. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_autoscaling_group_name"></a> [autoscaling\_group\_name](#output\_autoscaling\_group\_name) | Name of the autoscaling group managing the OpenVPN instances |
| <a name="output_cloudwatch_log_group_name"></a> [cloudwatch\_log\_group\_name](#output\_cloudwatch\_log\_group\_name) | Name of the CloudWatch Log Group for OpenVPN server logs |
| <a name="output_efs_dns_name"></a> [efs\_dns\_name](#output\_efs\_dns\_name) | DNS name of the EFS file system mount target for accessing shared OpenVPN configuration |
| <a name="output_efs_file_system_id"></a> [efs\_file\_system\_id](#output\_efs\_file\_system\_id) | ID of the EFS file system used for storing OpenVPN configuration and certificates |
| <a name="output_efs_security_group_id"></a> [efs\_security\_group\_id](#output\_efs\_security\_group\_id) | ID of the security group attached to the EFS file system for OpenVPN configuration storage |
| <a name="output_google_client_secret"></a> [google\_client\_secret](#output\_google\_client\_secret) | Google OAuth client secret name. The OpenVPN portal admin must update the secret with a Google OAuth client JSON. |
| <a name="output_google_directory_reader_client_id"></a> [google\_directory\_reader\_client\_id](#output\_google\_directory\_reader\_client\_id) | Numeric OAuth2 client ID of the directory-reader SA. Paste this into the<br/>Workspace Admin console (https://admin.google.com/ac/owl/domainwidedelegation)<br/>together with scope https://www.googleapis.com/auth/admin.directory.user.readonly.<br/>This is the one step Terraform cannot perform; verify-wif.sh prints it on the<br/>instance too. |
| <a name="output_google_directory_reader_sa_email"></a> [google\_directory\_reader\_sa\_email](#output\_google\_directory\_reader\_sa\_email) | Email of the keyless directory-reader service account. |
| <a name="output_google_wif_credential_config_json"></a> [google\_wif\_credential\_config\_json](#output\_google\_wif\_credential\_config\_json) | Keyless external-account credential config written to the instance. Contains<br/>no secret (only IDs + IMDS URLs). |
| <a name="output_launch_template_id"></a> [launch\_template\_id](#output\_launch\_template\_id) | ID of the EC2 launch template used by the OpenVPN Auto Scaling Group |
| <a name="output_launch_template_latest_version"></a> [launch\_template\_latest\_version](#output\_launch\_template\_latest\_version) | Latest version number of the OpenVPN launch template |
| <a name="output_load_balancer_arn"></a> [load\_balancer\_arn](#output\_load\_balancer\_arn) | ARN of the load balancer for the OpenVPN portal |
| <a name="output_nlb_arn"></a> [nlb\_arn](#output\_nlb\_arn) | ARN of the Network Load Balancer |
| <a name="output_nlb_dns_name"></a> [nlb\_dns\_name](#output\_nlb\_dns\_name) | DNS name of the Network Load Balancer serving OpenVPN traffic |
| <a name="output_nlb_security_group_id"></a> [nlb\_security\_group\_id](#output\_nlb\_security\_group\_id) | ID of the security group attached to the Network Load Balancer |
| <a name="output_openvpn-instance-role-arn"></a> [openvpn-instance-role-arn](#output\_openvpn-instance-role-arn) | ARN of the IAM role attached to the OpenVPN instance |
| <a name="output_openvpn_port"></a> [openvpn\_port](#output\_openvpn\_port) | TCP port number used by OpenVPN server for client connections |
| <a name="output_portal_url"></a> [portal\_url](#output\_portal\_url) | URL of the OpenVPN portal web interface |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the security group attached to OpenVPN Auto Scaling Group instances |
| <a name="output_target_group_arn"></a> [target\_group\_arn](#output\_target\_group\_arn) | ARN of the Network Load Balancer target group for OpenVPN instances |
| <a name="output_vpn_server_fqdn"></a> [vpn\_server\_fqdn](#output\_vpn\_server\_fqdn) | Fully qualified domain name (FQDN) of the OpenVPN server endpoint for client connections |
<!-- END_TF_DOCS -->
