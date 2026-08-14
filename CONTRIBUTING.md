# Contributing to this Project

Thank you for your interest in contributing! This document provides guidelines for contributing to this Terraform module.

## How to Contribute

### Reporting Issues

- Check existing issues before creating a new one
- Use a clear, descriptive title
- Include Terraform and provider versions
- Provide minimal reproduction steps
- Include relevant logs or error messages

### Submitting Changes

1. Fork the repository
2. Create a feature branch from `main`
3. Make your changes following our coding standards
4. Write or update tests as needed
5. Run `make test-clean` to verify all tests pass
6. Submit a pull request

### Pull Request Guidelines

- Reference any related issues
- Provide a clear description of changes
- Ensure CI checks pass
- Keep changes focused and atomic
- Update documentation if needed

## Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/REPO_NAME.git
cd REPO_NAME

# Install dependencies
make bootstrap

# Run tests (keeps infrastructure for debugging)
make test-keep

# Run tests with cleanup (before PR)
make test-clean
```

## Coding Standards

Please follow the coding standards defined in `.claude/CODING_STANDARD.md`:

- Use `terraform fmt` for formatting
- Follow naming conventions (snake_case)
- Add descriptions to all variables and outputs
- Include validation blocks where appropriate
- Use conventional commits for commit messages

## Commit Message Format

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: Add support for custom IAM policies
fix: Correct security group ingress rules
docs: Update README with new examples
refactor: Simplify variable validation logic
```

## Testing

- Tests use pytest with pytest-infrahouse fixtures
- Tests create real AWS infrastructure
- Always run `make test-clean` before submitting PR
- Ensure tests pass for all supported AWS provider versions

## Questions?

- Open a GitHub issue for questions about contributing
- See [SECURITY.md](SECURITY.md) for reporting security vulnerabilities

## Testing locally (integration tests)

This section describes how to test module changes in a development environment before deploying to production.

### Prerequisites

- Terraform >= 1.5
- Python 3.12+ (for pytest-based tests)
- AWS CLI configured with credentials
- GNU Make
- Pre-commit (optional, for local linting)

### Setting Up Development Environment

1. **Clone the repository**
   ```shell
   git clone https://github.com/infrahouse/terraform-aws-openvpn.git
   cd terraform-aws-openvpn
   ```

2. **Install Python dependencies**
   ```shell
   make bootstrap
   ```

   This installs:
   - `checkov` - Security scanning
   - `infrahouse-core` - InfraHouse toolkit utilities
   - `pytest-infrahouse` - Test fixtures and helpers

3. **Install pre-commit hooks**
   ```shell
   pre-commit install
   ```

   Hooks run automatically on `git commit`
   (see [.pre-commit-config.yaml](.pre-commit-config.yaml)):
   - `terraform fmt` - Format Terraform files
   - `terraform-docs` - Update README.md documentation
   - `tflint` - Terraform linting

   The repo hook installed by `make install-hooks` is preserved as
   `pre-commit.legacy` and still runs after the pre-commit hooks.

### Running Tests

The module includes comprehensive pytest-based integration tests.

#### Quick Test Run
```shell
# Run all tests
make test

# Run specific test file
pytest tests/test_openvpn.py -v

# Run specific test case
pytest tests/test_openvpn.py::test_module -v
```

#### Test Environment Variables

Tests require AWS credentials and optionally Google OAuth credentials:

```shell
# Required: AWS credentials (via AWS CLI profile or environment variables)
export AWS_DEFAULT_PROFILE=AWSAdministratorAccess-123456789012
export AWS_DEFAULT_REGION=us-west-1

# Optional: Google OAuth client secret for full integration test
export OPENVPN_CLIENT_SECRET='{"web": {"client_id": "...", "client_secret": "..."}}'

# Run tests
make test
```

#### What Tests Cover

1. **Infrastructure Creation** (`test_module`)
   - Creates full VPN infrastructure in AWS
   - Verifies all resources are created correctly
   - Checks Auto Scaling Group, NLB, EFS, ECS portal
   - Validates security groups and IAM roles

2. **Connectivity** (`test_vpn_connectivity`)
   - Deploys test EC2 instance in private subnet
   - Verifies VPN client can connect
   - Tests network connectivity to private resources

3. **Security** (via Checkov)
   - Scans for misconfigurations
   - Validates encryption settings
   - Checks for overly permissive security groups

#### Test Data Location

Test fixtures are in `test_data/`:
- `test_data/openvpn/` - Test configuration (turns the WIF feature on)
- `test_data/openvpn/ecr.tf` - Test ECR repository (for custom portal images)
- `test_data/openvpn/main.tf` - Test module invocation

### GCP credentials are required

Since v7.0.0 the module always requires a `google` provider, and
`tests/test_module.py` turns the WIF feature on. So the single integration test
stands the module up against AWS **and** the real GCP project in one run, and
also verifies the keyless federation (via `tests/wif_helpers.py`):

- the directory-reader service account exists and has **no** user-managed keys,
- the workload identity pool and its AWS provider exist and are `ACTIVE`,
- the service account grants `workloadIdentityUser` and
  `serviceAccountTokenCreator` to a `principalSet` scoped to that pool.

Because the module cannot apply without GCP, the test **fails** (not skips) when
GCP credentials are missing — there is no AWS-only path anymore.

#### Prerequisites

1. **Install the Google Cloud SDK** (provides `gcloud`):
   ```shell
   brew install --cask google-cloud-sdk
   ```

2. **Authenticate with Application Default Credentials (ADC).** Same mechanism
   locally and in CI, so no service-account key is stored:
   ```shell
   gcloud auth application-default login
   ```
   `gcloud auth application-default set-quota-project` is **not** needed — the
   test and provider pass the project explicitly (via `GOOGLE_PROJECT`), so the
   "quota project" warning google-auth prints is harmless. In CI, GCP auth is
   set up keylessly with `scripts/setup-ci-gcp-auth.sh` + `google-github-actions/auth`.

3. **GCP permissions.** Your identity needs, in the target project:
   - `roles/iam.serviceAccountAdmin`
   - `roles/iam.serviceAccountKeyAdmin` (the test lists SA keys to assert it is keyless)
   - `roles/iam.workloadIdentityPoolAdmin`
   - `roles/serviceusage.serviceUsageAdmin` (to enable the required APIs)

   The project must also have `cloudresourcemanager.googleapis.com` enabled (the
   google provider needs it to manage `google_project_service`).

4. **Python dependencies** (installed by `make bootstrap`):
   `google-api-python-client`, `google-auth`.

#### Running

```shell
make test-clean   # run, then destroy resources (uses GOOGLE_PROJECT, default openvpn-427715)
make test-keep    # run and keep resources for debugging
GOOGLE_PROJECT=my-project make test-clean   # override the project
```

The Workspace admin the SA impersonates defaults to `aleks@infrahouse.com`;
override with `GOOGLE_WORKSPACE_ADMIN_EMAIL`.

> **Note:** The one step Terraform cannot perform — authorizing the SA's client
> ID for the directory scope via
> [Domain-wide delegation](https://admin.google.com/ac/owl/domainwidedelegation)
> — is **not** exercised by the test. Each run generates a fresh service account
> (new client ID), so authorizing DWD per run is impractical; use
> [`verify-wif.sh`](#google-configuration) on an instance to
> check the delegation path by hand.

### Manual Testing Workflow

For testing changes before committing:

1. **Create a test branch**
   ```shell
   git checkout -b feature/my-improvement
   ```

2. **Make your changes**
   - Edit Terraform files
   - Update variable descriptions
   - Modify security group rules

3. **Run linters locally**
   ```shell
   make lint
   ```

   This runs:
   - `terraform fmt -check` - Verify formatting
   - `terraform validate` - Validate syntax
   - Additional InfraHouse linters

4. **Run Checkov security scan**
   ```shell
   checkov -d . --config-file .checkov.yml
   ```

5. **Update documentation**
   ```shell
   terraform-docs markdown table --output-file README.md --output-mode inject .
   ```

6. **Run integration tests**
   ```shell
   make test-keep
   make test-clean ## final run at the end
   ```

7. **Commit changes**
   ```shell
   git add .
   git commit -m "Add feature X"
   # Pre-commit hooks run automatically
   ```

### Testing in Isolated AWS Account

For safer testing, use a dedicated AWS account:

1. **Create test AWS account** (via AWS Organizations)

2. **Configure test environment**
   ```hcl
   # test_data/openvpn/main.tf
   module "vpn" {
     source = "../.."  # Local module path

     backend_subnet_ids = ["subnet-test1", "subnet-test2"]
     lb_subnet_ids      = ["subnet-public1", "subnet-public2"]
     zone_id            = "Z1234567890ABC"  # Test Route53 zone

     google_oauth_client_writer = "arn:aws:iam::123456789012:role/test-admin"

     # Use smaller instances for cost savings
     instance_type = "t3a.small"
     portal_instance_type = "t3.nano"

     # Shorter retention for test
     cloudwatch_log_retention_days = 7
     efs_backup_retention_days = 7
   }
   ```

3. **Apply test configuration**
   ```shell
   cd test_data/openvpn
   terraform init
   terraform apply
   ```

4. **Test functionality**
   - Download VPN profile from portal
   - Connect with OpenVPN client
   - Verify connectivity to test resources

5. **Destroy test resources**
   ```shell
   terraform destroy
   ```

### Debugging Failed Tests

#### View Terraform Output
```shell
# Enable Terraform debug logging
export TF_LOG=DEBUG
make test
```

#### Check CloudWatch Logs
```shell
# View bootstrap logs
aws logs tail /aws/openvpn/development/openvpn --follow

# View portal logs
aws logs tail /aws/ecs/openvpn-portal --follow
```

#### SSH to Test Instance
```shell
# Get instance IP from Terraform output
terraform output instance_private_ip

# SSH via Systems Manager (no key required)
aws ssm start-session --target i-1234567890abcdef0

# Or traditional SSH if key pair configured
ssh -i ~/.ssh/test-key.pem ubuntu@<instance-ip>
```

#### Common Test Failures

1. **Test timeout** - Increase `asg_health_check_grace_period`
2. **EFS mount failure** - Check security group rules
3. **Google OAuth errors** - Verify `OPENVPN_CLIENT_SECRET` environment variable
4. **Terraform state lock** - Clean up DynamoDB lock table

### CI/CD Pipeline Testing

The module uses GitHub Actions for automated testing:

- **Workflow:** `.github/workflows/terraform-CI.yml`
- **Runs on:** Pull requests to `main` branch
- **Steps:**
  1. Checkout code
  2. Configure AWS credentials (via OIDC)
  3. Set up Python environment
  4. Run linters (`make lint`)
  5. Run Checkov security scan
  6. Run integration tests (`make test`)

**View workflow runs:**
https://github.com/infrahouse/terraform-aws-openvpn/actions

### Best Practices for Testing

1. **Always test in isolated environment first**
   - Never test directly in production AWS account
   - Use dedicated test account or separate VPC

2. **Clean up test resources**
   - Run `terraform destroy` after testing
   - Check for orphaned resources (load balancers, security groups)

3. **Test both success and failure paths**
   - Verify module handles errors gracefully
   - Test with invalid inputs
   - Test resource limits (max instances, etc.)

4. **Document test scenarios**
   - Add comments to test files
   - Document expected behavior
   - Include reproduction steps for bugs

5. **Use version pinning for testing**
   - Pin provider versions in test configuration
   - Ensures reproducible test results

## License

By contributing, you agree that your contributions will be licensed under the same license as the project.
