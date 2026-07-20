# Configuration

Every input variable is grouped by purpose below. The authoritative, auto-generated table (with
full type signatures) lives in the [README](https://github.com/infrahouse/terraform-aws-openvpn#inputs).

## Required variables

These have no default — you must set them.

| Variable | Type | Description |
|----------|------|-------------|
| `alarm_emails` | `list(string)` | Email addresses that receive CloudWatch alarm notifications. |
| `backend_subnet_ids` | `list(string)` | Private subnets for the OpenVPN instances and portal tasks. |
| `lb_subnet_ids` | `list(string)` | Public subnets for the Network Load Balancer. |
| `zone_id` | `string` | Route 53 hosted zone ID for the VPN and portal DNS records. |
| `google_oauth_client_writer` | `string` | IAM role ARN allowed to update the Google OAuth secret. |
| `replication_region` | `string` | Region for cross-region replication of the portal ALB access-log bucket. |

!!! warning "`replication_region` must differ from the deploy region"
    A same-region replica still fails the Vanta `aws-s3-cross-region-replication-enabled` test. For
    a `us-west-2` deployment, `us-east-1` is a valid replica; a `us-east-1` deployment must pick a
    different region such as `us-west-2`.

## Identity & service

| Variable | Default | Description |
|----------|---------|-------------|
| `environment` | `"development"` | Environment name; applied as a tag. Set this explicitly in production. |
| `service_name` | `"openvpn"` | Service name; used as a prefix for resources and the portal. |

## Authentication

| Variable | Default | Description |
|----------|---------|-------------|
| `allowed_domains` | `[]` | Extra Google domains allowed to connect. The `zone_id` domain is always included. |
| `users` | `null` | Optional user definitions passed through to the portal. |

## OpenVPN server (ASG)

| Variable | Default | Description |
|----------|---------|-------------|
| `instance_type` | `"c6in.large"` | EC2 instance type for OpenVPN servers. |
| `asg_ami` | `null` | Override AMI. Defaults to the latest Ubuntu Pro image for `ubuntu_codename`. |
| `ubuntu_codename` | `"noble"` | Ubuntu release used for the server image. |
| `asg_min_size` | `null` | Minimum instances. Defaults to one per AZ. |
| `asg_max_size` | `null` | Maximum instances. Defaults based on AZ count. |
| `asg_health_check_grace_period` | `600` | Seconds before health checks apply to a new instance. |
| `asg_instance_refresh_max_healthy_percentage` | `110` | Max healthy percentage during instance refresh. |
| `on_demand_base_capacity` | `null` | Base count of On-Demand instances (rest may be Spot). |
| `autoscaling_target_cpu` | `60` | Target CPU utilization (%) for scaling. |
| `autoscaling_target_network_percentage` | `60` | Target network bandwidth (% of baseline) for scaling. |
| `root_volume_size` | `30` | Root EBS volume size in GB. |
| `routes` | `[]` | Networks pushed to clients, e.g. `[{network="10.0.0.0", netmask="255.0.0.0"}]`. |
| `key_pair_name` | `null` | SSH key pair for instance access. A key is generated if unset. |

## Portal (ECS)

| Variable | Default | Description |
|----------|---------|-------------|
| `portal-image` | `public.ecr.aws/infrahouse/openvpn-portal:latest` | Portal Docker image. |
| `portal_instance_type` | `"t3a.small"` | EC2 instance type backing the portal ECS service. |
| `portal_task_min_count` | `null` | Minimum portal tasks. Defaults to one per backend subnet. |
| `portal_task_max_count` | `null` | Maximum portal tasks. Defaults to min + 1. |
| `portal_workers_count` | `4` | Number of uvicorn workers per portal task. |
| `smtp_credentials_secret` | `null` | Secret with SMTP credentials for portal email. |

## Storage & backup

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_efs_backup` | `true` | Enable AWS Backup for the EFS config volume. |
| `efs_backup_schedule` | `"cron(0 2 * * ? *)"` | Backup schedule (cron). |
| `efs_backup_retention_days` | `365` | Backup retention in days. |

## Logging & monitoring

| Variable | Default | Description |
|----------|---------|-------------|
| `cloudwatch_log_retention_days` | `365` | Retention for OpenVPN server logs. |
| `cloudwatch_namespace` | `"OpenVPN/System"` | CloudWatch metrics namespace. |
| `sns_topic_alarm_arn` | `null` | Optional SNS topic for alarm notifications. |
| `alb_access_log_force_destroy` | `false` | Destroy the portal access-log bucket even if non-empty. |

## Provisioning (advanced)

| Variable | Default | Description |
|----------|---------|-------------|
| `packages` | `[]` | Extra apt packages to install on the server. |
| `extra_repos` | `{}` | Additional apt repositories. |
| `extra_files` | `[]` | Extra files to write via cloud-init. |
| `cloudinit_extra_commands` | `[]` | Extra cloud-init commands. |
| `extra_policies` | `{}` | Extra IAM policies to attach to the instance role. |
| `extra_instance_profile_permissions` | `null` | Extra inline instance-profile permissions. |
| `gzip_userdata` | `true` | Gzip user data to stay under the EC2 16 KB limit. |
| `puppet_*` | varies | Puppet runtime settings (manifest, module path, hiera config, etc.). |

## Google directory revocation (keyless WIF)

Optional. Lets the OpenVPN instance read Google Workspace user suspension status
— via Workload Identity Federation, so **no service-account key is stored** — in
order to revoke deactivated users' certificates. Enabled with a single flag.

Because the module can create GCP resources, it requires a `google` provider
(v7.0.0+). With the feature off (default) that provider may be an empty,
uncredentialed block — it is never configured. See the
[README upgrade note](https://github.com/infrahouse/terraform-aws-openvpn#upgrading-to-v700).

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_google_directory_revocation` | `false` | Turn the feature on. Creates the GCP resources, writes the files to the instances, and schedules the Puppet revocation sync. |
| `google_workspace_admin_email` | `null` | Email of a **real** Workspace admin the VPN impersonates to read the directory. Required when the feature is on. |
| `google_wif_pool_id` | `openvpn-wif-pool` | Workload identity pool ID. |
| `google_wif_provider_id` | `aws-openvpn` | Workload identity pool *provider* ID. |
| `google_directory_reader_sa_id` | `openvpn-dir-reader` | Account ID of the keyless directory-reader service account. |

### Required manual step: domain-wide delegation

Terraform creates everything except one thing — there is no resource in
`hashicorp/google` to authorize the service account for the directory scope.
A Workspace **super admin** must do this once:

1. Open <https://admin.google.com/ac/owl/domainwidedelegation>
   (menu path: Security → Access and data control → API controls →
   Manage Domain-Wide Delegation).
2. Click **Add new** and enter:
    - **Client ID** — the service account's numeric OAuth client ID
      (`google_directory_reader_client_id` output).
    - **OAuth scopes** — `https://www.googleapis.com/auth/admin.directory.user.readonly`
3. Click **Authorize**.

Running `sudo /opt/openvpn-wif/verify-wif.sh` on any OpenVPN instance prints
these exact values (read from `/opt/openvpn-wif/wif.env`) and then verifies the
whole federation chain. Authorization takes a few minutes to propagate, so an
`unauthorized_client` error right after authorizing is expected — re-run the
script. See the
[README](https://github.com/infrahouse/terraform-aws-openvpn#google-directory-revocation-keyless-wif)
for the full walkthrough.

### Related outputs

| Output | Description |
|--------|-------------|
| `google_directory_reader_sa_email` | Email of the keyless directory-reader service account. |
| `google_directory_reader_client_id` | Numeric OAuth client ID to paste into domain-wide delegation. |
| `google_wif_credential_config_json` | Keyless external-account credential config (contains no secret). |

## Outputs

| Output | Description |
|--------|-------------|
| `vpn_server_fqdn` | FQDN clients connect to. |
| `portal_url` | URL of the portal web interface. |
| `google_client_secret` | Name of the Google OAuth secret to populate. |
| `openvpn_port` | TCP/UDP port for OpenVPN connections. |
| `nlb_dns_name` / `nlb_arn` | Network Load Balancer DNS name and ARN. |
| `load_balancer_arn` | Portal ALB ARN. |
| `autoscaling_group_name` | OpenVPN ASG name. |
| `launch_template_id` / `launch_template_latest_version` | OpenVPN launch template identifiers. |
| `efs_file_system_id` / `efs_dns_name` | EFS config volume identifiers. |
| `security_group_id` / `nlb_security_group_id` / `efs_security_group_id` | Security group IDs. |
| `openvpn-instance-role-arn` | IAM role ARN attached to OpenVPN instances. |
| `target_group_arn` | NLB target group ARN. |
| `cloudwatch_log_group_name` | OpenVPN server log group name. |
