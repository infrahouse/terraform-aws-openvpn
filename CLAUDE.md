# terraform-aws-openvpn Project Context

## First Steps

**Your first tool call in this repository MUST be reading `.claude/CODING_STANDARD.md`
and `.claude/TERRAFORM_MODULE_REQUIREMENTS.md`.
Do not read any other files, search, or take any actions until you have read them.**
These contain InfraHouse's comprehensive coding standards for Terraform, Python, general formatting rules,
and module repository requirements (README structure, badges, GitHub Pages docs, required files).

## Project Overview

This Terraform module deploys a production-ready OpenVPN server on AWS with Google OAuth 2.0 authentication.
The module is part of the InfraHouse collection of infrastructure modules.

**Key Features:**
- OpenVPN server with Google OAuth authentication
- Multi-domain support (version 4.0.0+)
- Auto Scaling group with Network Load Balancer
- OpenVPN Portal (ECS service) for web-based profile management
- EFS-backed configuration storage (encrypted)
- ISO 27001 compliance considerations

**Architecture:**
- OpenVPN servers run in Auto Scaling groups in private subnets
- Network Load Balancer in public subnets for external access
- OpenVPN Portal as ECS service for user authentication and profile distribution
- EFS for shared configuration across OpenVPN instances
- Route 53 integration for DNS management

## Module Purpose

**Problem it solves:**
- Provides secure VPN access to AWS private resources
- Centralizes authentication via Google OAuth
- Eliminates manual OpenVPN certificate management
- Supports teams across multiple Google domains

**Use case:**
Users authenticate via Google, download their OpenVPN profile from the portal,
and connect to access AWS resources in private subnets.

## Technical Requirements

### Infrastructure
- **AWS Provider:** Supports versions 5.11 through 6.x
- **Terraform:** Requires ~> 1.5
- **Subnets:** Requires both private (backend) and public (load balancer) subnets
- **VPC:** Must have existing VPC with proper networking setup

### Components
1. **OpenVPN Server**
    - Default instance type: `c6in.large` (compute-optimized for VPN encryption workloads)
    - Runs on Ubuntu (configurable via `ubuntu_codename`, default: "noble")
    - Managed via Auto Scaling group
    - Stores config on EFS (encrypted)
    - Health check grace period: 600 seconds (10 minutes)

2. **OpenVPN Portal**
    - ECS service running on Fargate or EC2
    - Default instance type: `t3.small`
    - Docker image: `public.ecr.aws/infrahouse/openvpn-portal:latest`
    - Requires Google OAuth client credentials in AWS Secrets Manager
    - Flask-based web application with uvicorn workers

3. **Networking**
    - Network Load Balancer for OpenVPN traffic
    - Security groups for OpenVPN (UDP 1194), SSH, ICMP
    - EFS security group for config sharing
    - Route tables for VPN client routing

### Required Variables
- `backend_subnet_ids`: Private subnets for OpenVPN instances
- `lb_subnet_ids`: Public subnets for Network Load Balancer
- `google_oauth_client_writer`: IAM role ARN that can update Google OAuth secret
- `zone_id`: Route 53 zone ID for DNS records

### Optional but Important Variables
- `allowed_domains`: List of Google domains allowed to connect (auto-includes zone domain)
- `routes`: Network routes to push to VPN clients (format: `[{network: "10.0.0.0", netmask: "255.0.0.0"}]`)
- `asg_min_size` / `asg_max_size`: Auto Scaling limits (defaults calculated based on AZ count)
- `key_pair_name`: SSH key for instance access

## InfraHouse Standards

**Follow the coding standards documented in `.claude/CODING_STANDARD.md`
and module requirements in `.claude/TERRAFORM_MODULE_REQUIREMENTS.md`.**

## Build & Development Commands

```bash
make bootstrap          # Install dev dependencies (pip, requirements.txt, git hooks)
make lint               # Check formatting (yamllint + terraform fmt -check)
make format             # Auto-format (terraform fmt + black tests portal)
make docs               # Regenerate README.md via terraform-docs
```

### Testing

Tests are **integration tests** that create real AWS infrastructure via pytest-infrahouse.

```bash
make test-keep          # Run tests, keep infrastructure for debugging
make test-clean         # Run tests, destroy infrastructure after (run before PRs)

# Run a single test (aws5 or aws6 provider version):
pytest -xvvs \
    --aws-region=us-west-2 \
    --test-role-arn="arn:aws:iam::303467602807:role/openvpn-tester" \
    -k aws6 \
    tests/test_module.py
```

### Releases

Must be on `main` branch. Version tracked in `.bumpversion.cfg` and `locals.tf` (`module_version`).

```bash
make release-patch      # x.x.PATCH
make release-minor      # x.MINOR.0
make release-major      # MAJOR.0.0
```

## Related InfraHouse Modules

This module uses other InfraHouse modules:
- `infrahouse/instance-profile/aws` - IAM instance profiles
- `infrahouse/secret/aws` - Secret management
- `infrahouse/ecs/aws` - ECS service for portal
- `infrahouse/cloud-init/aws` - User data generation

## Development Workflow

1. **Make changes:** Edit Terraform files following InfraHouse conventions
2. **Update docs:** Run `make docs` to regenerate README
3. **Run tests:** Execute `make test-keep` to run pytest tests
4. **Run tests and clean resources:** Execute `make test-clean` to run pytest tests
   with instructions to destroy resources after the test
5. **Create PR:** Use conventional commits format
6. **CI/CD:** GitHub Actions will run `terraform plan` on PR
7. **Merge:** After approval, merge triggers deployment

## Common Tasks

### Adding a new variable
1. Add to `variables.tf` with detailed description
2. Use in appropriate resource file
3. Update tests if needed
4. Run `make docs` to update README

### Modifying OpenVPN configuration
- Configuration is in cloud-init user data (see `portal/` directory)
- EFS stores persistent OpenVPN certificates and config
- Changes require instance refresh in Auto Scaling group

### Debugging
- Check CloudWatch logs for OpenVPN portal
- SSH to OpenVPN instances using key pair
- Verify EFS mounts and permissions
- Check security group rules
- Review Auto Scaling group activity

## Google OAuth Setup

The module creates a placeholder secret for Google OAuth credentials. After initial deployment:

1. Create OAuth 2.0 Client ID in Google Cloud Console
2. Configure authorized origins: `https://openvpn-portal.<your-domain>`
3. Configure redirect URIs: `https://openvpn-portal.<your-domain>/login/google/authorized`
4. Download client secret JSON
5. Update AWS secret using `ih-secrets` or AWS CLI
6. Portal will detect updated secret and enable authentication

## Important Notes

### Security
- All EFS volumes are encrypted
- OpenVPN CA passkey randomly generated and stored in Secrets Manager
- Google OAuth provides authentication layer
- Instance profile permissions follow least-privilege principle

### Scalability
- Auto Scaling group handles instance failures
- Can scale based on CPU utilization
- EFS provides shared config across instances
- Health checks ensure only healthy instances receive traffic

### Monitoring
- CloudWatch alarms for CPU utilization
- Module users must provide alert_emails variable for CloudWatch alerts
- Can integrate with SNS for alerts (`sns_topic_alarm_arn`)
- Portal logs to CloudWatch
- OpenVPN server logs accessible via SSH

### Multi-Domain Support
- Version 4.0.0+ supports multiple Google domains
- Requires making OpenVPN App "external" in Google Cloud Console
- Domain from `zone_id` automatically included in `allowed_domains`
- Additional domains specified via `allowed_domains` variable

## Known Gaps (vs. InfraHouse Standards)

Per `.claude/TERRAFORM_MODULE_REQUIREMENTS.md`, the following are currently missing:
- **`examples/` directory** — Required by both CODING_STANDARD.md and TERRAFORM_MODULE_REQUIREMENTS.md
- **GitHub Pages docs** — Only `docs/index.md` exists. Missing required pages:
  `getting-started.md`, `architecture.md`, `configuration.md`, `examples.md`,
  `troubleshooting.md`, `changelog.md`
