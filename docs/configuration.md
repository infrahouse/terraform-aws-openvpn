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

## Google configuration

The module touches Google in two ways, **both always on** (there is no feature
flag):

- **Portal login (OAuth):** VPN users authenticate with Google to download their
  profile.
- **Directory revocation (keyless Workload Identity Federation):** the OpenVPN
  instance asks Workspace *"which users are suspended?"* and revokes their VPN
  certificates — **with no service-account key at rest**. Trust chain:

  ```
  EC2 instance role -> GCP STS (federation) -> directory-reader service account
                    -> domain-wide delegation (acts as a Workspace admin)
                    -> Directory API
  ```

Because it always manages GCP resources, the module **requires a configured
`google` provider**.

**Two service accounts are involved — don't confuse them:**

| Service account | Created by | Used by | Purpose |
|-----------------|------------|---------|---------|
| directory-reader (`<service_name>-dir-reader-<random>`) | **this module** (Terraform) | the OpenVPN instance | read the Workspace directory, keyless via WIF |
| CI runner (your choice of name) | **you**, out of band (see [CI/CD](#in-cicd)) | GitHub Actions | let Terraform authenticate to GCP in CI |

### 1. OAuth client (portal login)

VPN users log into the portal with Google, so you need a Google OAuth 2.0 client
and its secret in AWS Secrets Manager. In the Google Cloud Console create an
OAuth 2.0 Client ID with the portal's authorized origin and redirect URI, then
write the downloaded secret into the placeholder secret the module created. The
full click-through is Step 4 of the
[README Installation walkthrough](https://github.com/infrahouse/terraform-aws-openvpn#installation).

### 2. Terraform's Google provider credentials

The module always manages GCP resources, so `plan`/`apply` always needs a
**configured** `google` provider.

#### Pick a GCP project

Everything below goes into one **GCP project** (the module creates its resources
there). What you need is the project's **ID** — a globally-unique string of
lowercase letters, digits, and hyphens, 6–30 chars, e.g. `acme-openvpn` or
`openvpn-427715` (note: the ID, *not* the display name or the numeric project
number).

**Already have one?** List your projects (use the `PROJECT_ID` column), or find
it in the [Cloud Console](https://console.cloud.google.com/) project picker:

```shell
gcloud projects list
```

**Need one?** Create it (or use the console), then make sure billing is enabled:

```shell
gcloud projects create acme-openvpn
```

Use that ID everywhere `YOUR_GCP_PROJECT` appears below.

#### Pick a Workspace admin (one per tenant)

`google_workspace_admin_emails` is a **list** — the Google Workspace admin the VPN
impersonates (via domain-wide delegation) to read who has been deactivated, **one
per Workspace tenant** whose users you allow to connect. Each entry must be:

- a **real, active user** in *its* Workspace — a made-up address fails at runtime
  with `invalid_grant: Invalid email or User ID`;
- an **admin allowed to read the directory** — a super admin, or a custom admin
  role with the *Users → Read* privilege.

A dedicated role account (e.g. `automation-admin@your-domain.com`) is often
cleaner than a specific person, so revocation doesn't break when someone leaves.
Confirm each account exists under
[Admin console → Directory → Users](https://admin.google.com/ac/users).

> **One list, one SA, many Workspaces.** A GCP project is not a Google Workspace.
> This module creates a **single** directory-reader service account in your one
> GCP project; you authorize that same SA client ID via domain-wide delegation in
> **each** Workspace's Admin console (see the DWD step below) and list one admin
> per Workspace here. If your allowed domains are separate Workspace tenants (e.g.
> `acme.io` and `acme.dev`), you need an entry for each — otherwise deactivated
> users in the un-listed tenant keep working VPN certs. One tenant = a one-element
> list.

#### Declare the provider

Declare `google` once and thread it through every module hop that uses an
explicit `providers` map (it is not auto-inherited through an explicit map):

```hcl
provider "google" {
  project = "YOUR_GCP_PROJECT"   # the ID from above; credentials come from ADC, below
}

module "openvpn" {
  source  = "registry.infrahouse.com/infrahouse/openvpn/aws"
  version = "10.1.0"
  providers = {
    aws     = aws
    aws.dns = aws
    google  = google   # <-- required
  }
  # ...
  # One REAL, active admin per Workspace tenant:
  google_workspace_admin_emails = ["admin@example.com", "admin@example.dev"]
}
```

The provider authenticates via Application Default Credentials (ADC), the same
mechanism locally and in CI — no service-account key is ever stored.

#### On your laptop

```shell
gcloud auth application-default login
export GOOGLE_PROJECT=YOUR_GCP_PROJECT      # same project ID as above
```

Ignore the `gcloud` "no quota project" warning — everything targets the project
explicitly, so no quota project is needed.

#### In CI/CD

Keyless, via GitHub OIDC → GCP federation, mirroring how CI already authenticates
to AWS. This one-time bootstrap creates a CI runner service account, a GitHub
OIDC pool + provider locked to your repo, the impersonation binding, and the
project roles the runner needs (and enables the required APIs) — **no
service-account key**. Do it once, locally, with GCP owner/ADC credentials, via
**Terraform** or the **bash script** — same result, pick whichever fits.

**Option A — Terraform.** Apply the
[`ci-gcp-auth`](https://github.com/infrahouse/terraform-aws-openvpn/tree/main/modules/ci-gcp-auth)
submodule:

```hcl
provider "google" { project = "YOUR_GCP_PROJECT" }

module "ci_gcp_auth" {
  source      = "registry.infrahouse.com/infrahouse/openvpn/aws//modules/ci-gcp-auth"
  project     = "YOUR_GCP_PROJECT"
  github_repo = "your-org/your-repo"
}

output "github_actions_auth_step" { value = module.ci_gcp_auth.github_actions_auth_step }
```

```shell
gcloud auth application-default login
terraform init && terraform apply
```

**Option B — bash script.** Fetch it (works from any directory):

```shell
curl -fsSL -o setup-ci-gcp-auth.sh \
  https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/scripts/setup-ci-gcp-auth.sh
```

Review it — it creates IAM resources:

```shell
less setup-ci-gcp-auth.sh
```

Set **your** project and repo (it has no defaults, so it can't target the wrong
project), then run it (idempotent):

```shell
export GOOGLE_PROJECT=YOUR_GCP_PROJECT
export GITHUB_REPO=your-org/your-repo
```

```shell
bash setup-ci-gcp-auth.sh
```

**Then wire it up.** Both options print a ready-to-paste step (the Terraform
`github_actions_auth_step` output, or the script's final block). Add it to
**both** the plan and apply workflows (each job needs
`permissions: id-token: write`):

```yaml
- name: Configure GCP Credentials
  uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL/providers/PROVIDER
    service_account: RUNNER_SA@PROJECT.iam.gserviceaccount.com
```

That step writes ADC the `google` provider (and the tests) pick up.

### 3. GCP resources (directory revocation)

#### Created by Terraform

`terraform apply` creates the keyless directory-reader SA, the workload-identity
pool + AWS provider, the two IAM bindings, and enables the `sts`,
`iamcredentials`, `iam`, and `admin` APIs. It also rolls a new launch template,
so the ASG **refreshes its instances**; each new OpenVPN instance receives three
files via cloud-init:

| File | Purpose |
|------|---------|
| `/opt/openvpn-wif/google-wif.json` | Keyless credential config (no secret — only IDs and IMDS URLs) |
| `/opt/openvpn-wif/wif.env` | SA email, SA client ID, locked role ARN, admin subject |
| `/opt/openvpn-wif/verify-wif.sh` | Read-only verification script (see [Verify the chain](#4-verify-the-chain)) |

The WIF chain now exists, but domain-wide delegation is not yet authorized, so
the sync reports "not ready" and revokes nothing — a safe intermediate state.

Inputs:

| Variable | Default | Description |
|----------|---------|-------------|
| `google_workspace_admin_emails` | *required* | List of **real** Workspace admins the VPN impersonates to read the directory — one per Workspace tenant. |
| `google_wif_pool_id` | `<service_name>-wif-pool-<random>` | Workload identity pool ID. Set to pin a fixed name. |
| `google_wif_provider_id` | `aws-<service_name>-<random>` | Workload identity pool *provider* ID. Set to pin a fixed name. |
| `google_directory_reader_sa_id` | `<service_name>-dir-reader-<random>` | Account ID of the keyless directory-reader SA. Set to pin a fixed name. |

!!! info "Two deployments can share one GCP project"
    These three names default to a **random, stable-in-state suffix**, so two
    OpenVPN deployments — even both with `service_name = "openvpn"` — create their
    WIF resources in the same GCP project without colliding. The suffix is
    generated once and never churns.

    **Upgrading an existing (pre-10.0.0) deployment:** the old fixed defaults were
    `openvpn-wif-pool`, `aws-openvpn`, `openvpn-dir-reader`. To avoid recreating
    the SA (a new SA gets a new client ID → you'd have to re-authorize
    domain-wide delegation), **pin the old names** on the existing deployment:

    ```hcl
    google_wif_pool_id            = "openvpn-wif-pool"
    google_wif_provider_id        = "aws-openvpn"
    google_directory_reader_sa_id = "openvpn-dir-reader"
    ```

Outputs:

| Output | Description |
|--------|-------------|
| `google_directory_reader_sa_email` | Email of the keyless directory-reader service account. |
| `google_directory_reader_client_id` | Numeric OAuth client ID to paste into domain-wide delegation. |
| `google_wif_credential_config_json` | Keyless external-account credential config (contains no secret). |

#### Manual, once: authorize domain-wide delegation

This is the **only** part Terraform cannot do — no resource exists in
`hashicorp/google` for it. It requires a Workspace **super admin**, and you do it
**once in every Workspace tenant** you listed in `google_workspace_admin_emails`
— pasting the **same** client ID + scope into each Workspace's Admin console. A
tenant you skip leaves its deactivated users un-revoked; `verify-wif.sh` Tier 4
checks every subject and stays red until they are all authorized.

Get the exact values by running the verification script on any OpenVPN
instance — it reads them from `wif.env`, so no `gcloud` or `terraform output`
is needed:

```shell
sudo /opt/openvpn-wif/verify-wif.sh
```

Until delegation is authorized, Tier 4 fails and prints the exact block to act
on (once it is authorized the block is no longer shown):

```text
=== Tier 4: domain-wide delegation -> Directory API ===
FAIL Tier 4 [admin@example.com]: domain-wide delegation rejected (unauthorized_client: ...).
FAIL Tier 4: 1 of 1 Workspace(s) rejected DWD: admin@example.com.
  Domain-wide delegation setup (one-time, requires a Workspace super admin):
    1. Open https://admin.google.com/ac/owl/domainwidedelegation
    2. Click 'Add new' and enter exactly:
         Client ID:    110312795661293035653
         OAuth scopes: https://www.googleapis.com/auth/admin.directory.user.readonly
    3. Click Authorize.
  Authorize the client id in EACH failing Workspace's Admin console, then
  re-run (authorization takes a few minutes to propagate).
```

With more than one tenant, Tier 4 prints one line per Workspace and stays red
until **every** one is authorized.

Follow those three steps in the Workspace Admin console. The menu path, if you
prefer navigating, is **Security → Access and data control → API controls →
Manage Domain-Wide Delegation**.

> **Note:** The Client ID must be the service account's **numeric** OAuth client
> ID (also available as the `google_directory_reader_client_id` output), not the
> service account email.

### 4. Verify the chain

Re-run the script. Authorization takes **a few minutes to propagate**, so an
`unauthorized_client` error immediately after clicking Authorize is expected —
simply re-run:

```shell
sudo /opt/openvpn-wif/verify-wif.sh
```

It checks the chain one link at a time, so a failure pinpoints the broken link:

| Tier | Proves |
|------|--------|
| 1 | The instance presents the assumed-role ARN the WIF provider is locked to |
| 2 | Federation exchange: AWS role → GCP federated token |
| 3 | Impersonation: `workloadIdentityUser` + `serviceAccountTokenCreator` bindings work |
| 4 | Domain-wide delegation → Directory API returns suspended users |

Success looks like:

```text
PASS Tier 1: instance ARN matches the locked role
PASS Tier 2: federated token minted: ya29.d.c0AZ4bNp... ...
PASS Tier 3: SA-impersonation token minted: ya29.c.c0AZ4bNp... ...
PASS Tier 4 [admin@example.com]: read suspended users via DWD: []
=== All requested tiers passed ===
```

An empty list simply means no users are currently suspended — the API call
succeeded.

The script is **read-only**: it verifies and reports, never installs or
modifies anything. It requires `google-auth >= 2` and `google-api-python-client`,
which must be pre-installed (the distro `python3-google-auth` package is far too
old — it lacks both `external_account` and `impersonated_credentials`). It runs
on the infrahouse-toolkit embedded interpreter
(`/opt/infrahouse-toolkit/embedded/bin/python3`) when present, otherwise system
`python3`; override with `WIF_PYTHON`.

### 5. The revocation sync (lives outside this module)

Steps 3–4 prove the *authentication* chain. The revocation itself is a daily
cron, `openvpn_google_user_sync`, that Puppet installs on the instance: it
reconciles the certificate index against the directory and revokes the
certificate of every user who is no longer active. The server's own certificate
is never a candidate.

Two dependencies live **outside this module**, so applying this module alone does
not begin revoking:

| Dependency | Provides | Minimum |
|------------|----------|---------|
| `puppet-code` | the fact-gated `openvpn_google_user_sync` cron + wrapper | a release including the feature |
| `infrahouse-toolkit` | `ih-openvpn sync-google-users` | **2.61.0** |

Both ship in the InfraHouse APT repo. The wrapper gates itself at runtime — until
the toolkit and the domain-wide delegation are both in place it reports "not
ready" and revokes nothing — so there is no unsafe, half-activated state.

**Preview first.** `--dry-run` reconciles and reports without touching the PKI:

```shell
. /opt/openvpn-wif/wif.env
ih-openvpn sync-google-users --dry-run     # lists who WOULD be revoked
```

Run it for real (or wait for the cron) and confirm — a revoked certificate shows
state `R` in the index:

```shell
ih-openvpn sync-google-users               # revokes now; the cron does the same daily
ih-openvpn list-clients
```

Revocation regenerates the CRL, which OpenVPN re-reads on each new connection, so
a revoked user is refused at their next handshake.

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
