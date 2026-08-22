# Troubleshooting

Common issues and how to diagnose them.

## Portal shows an authentication error

**Symptom:** Signing in fails, or the portal reports the OAuth client is not configured.

**Cause:** The Google OAuth secret still holds the placeholder value, or the redirect URI does not
match.

**Fix:**

1. Confirm the secret named by the `google_client_secret` output contains your real client JSON.
2. In the Google Cloud Console, verify the redirect URI is exactly
   `https://openvpn-portal.<your-domain>/login/google/authorized`.
3. Verify the JavaScript origin is `https://openvpn-portal.<your-domain>`.
4. See [Google configuration](configuration.md#google-configuration).

## "Access denied" for a valid Google user

**Symptom:** A user authenticates with Google but is rejected by the portal.

**Cause:** Their email domain is not in the allowed set.

**Fix:** Add the domain to [`allowed_domains`](configuration.md#authentication). The domain from
`zone_id` is always allowed. For more than one domain, the Google OAuth app must be marked
**External**.

## Client connects but cannot reach private resources

**Symptom:** The VPN tunnel comes up, but internal hosts are unreachable.

**Cause:** No routes are pushed to clients, or security groups block the traffic.

**Fix:**

1. Set [`routes`](configuration.md#openvpn-server-asg) for the private CIDRs you need to reach.
2. Confirm target security groups allow inbound traffic from the OpenVPN instances
   (`security_group_id` output).
3. Check route tables for the destination subnets.

## Instances cycle / fail health checks

**Symptom:** The ASG repeatedly replaces instances.

**Cause:** Instances need time to mount EFS and start OpenVPN before health checks apply.

**Fix:**

- The default `asg_health_check_grace_period` is 600s; increase it if bootstrap is slow.
- Check that the EFS mount target and `efs_security_group_id` allow NFS from the instances.
- Review the OpenVPN log group (`cloudwatch_log_group_name` output) and instance system logs.

## Portal access-log bucket fails the Vanta CRR test

**Symptom:** `aws-s3-cross-region-replication-enabled` fails for `vpn-po-access-log-*`.

**Cause:** `replication_region` is unset, or equals the deploy region.

**Fix:**

- Set [`replication_region`](configuration.md#required-variables) to a region **different** from
  where the module is deployed.
- For pre-existing objects, run an S3 Batch Replication job to backfill so the bucket goes green.

## EFS data missing after instance replacement

**Symptom:** Certificates or config appear lost after an instance is replaced.

**Cause:** Config lives on EFS, not on the instance — data loss usually means a mount problem, not
the replacement itself.

**Fix:**

- Confirm the instance mounted EFS (`efs_dns_name` / `efs_file_system_id` outputs).
- If EFS itself was recreated, restore from AWS Backup (enabled by default).

## Instance is invisible to AWS Inspector

**Symptom:** An OpenVPN instance still carries the `InspectorEc2Exclusion` tag after it finished
bootstrapping, so Inspector never scans it.

**Cause:** The ASG tags instances at launch and Puppet (`profile::boot_security_upgrade`) removes the tag
once security updates are applied. Removal is best effort and never fails a Puppet run, so a missing
`ec2:DeleteTags` permission leaves the tag — and the instance — in place silently.

**Fix:**

- Confirm the tag is actually still there:
  ```bash
  aws ec2 describe-tags --filters Name=resource-id,Values=i-...
  ```
- Look for the removal attempt in the instance's `/var/log/cloud-init-output.log`:
    - `removed InspectorEc2Exclusion from i-...` — the API call succeeded
    - `could not remove ... (no ec2:DeleteTags?)` — the instance profile is missing the permission
- The module grants `ec2:DeleteTags` scoped to that tag key on instances in its own ASG. If the instance
  was launched by an older version of the module, replace it — `propagate_at_launch` tags are only applied
  at launch, so the fix takes effect on the next instance refresh.

## Google directory revocation (WIF) fails

Run `sudo /opt/openvpn-wif/verify-wif.sh` on an OpenVPN instance. It tests the
chain one link at a time, so the first failing tier tells you where to look.

| Symptom | Cause / fix |
|---------|-------------|
| Tier 1 fails, or the ARN does not match | The instance is not using the role the WIF provider is locked to. Compare with the provider's `attribute_condition`. |
| Tier 2 fails | Federation rejected — usually the AWS role ARN does not match the attribute condition, or the pool/provider is not `ACTIVE`. |
| Tier 3 fails | The `workloadIdentityUser` / `serviceAccountTokenCreator` bindings on the service account are missing. |
| Tier 4: `unauthorized_client` | The subject is valid, but the SA's client ID is not authorized for the scope. Complete [domain-wide delegation](configuration.md#manual-once-authorize-domain-wide-delegation). Just authorized it? Wait a few minutes and re-run — propagation is not instant. |
| Tier 4: `invalid_grant: Invalid email or User ID` | Google cannot find the subject: an entry in `google_workspace_admin_emails` is not a real, active user in that Workspace. |
| `google-auth is installed but too old` | The distro `python3-google-auth` (1.5.x) lacks `external_account` and `impersonated_credentials`. Install `google-auth >= 2` and `google-api-python-client`. |

The script is read-only — it never installs or changes anything.

## Portal Shows 502 Bad Gateway

**Symptoms:** Accessing https://openvpn-portal.yourcompany.com returns a 502 error.

**Common causes:**
1. **Google OAuth credentials not configured** - The most common issue after initial deployment
   ```shell
   # Check if the secret has a value
   ih-secrets --aws-region us-west-1 --aws-profile YourProfile get google_client_XXXX
   # If it returns "NoValue", follow Step 4 in the Installation section
   ```

2. **ECS tasks failing to start** - Check CloudWatch Logs for the portal service
   ```shell
   # View recent logs
   aws logs tail /aws/ecs/openvpn-portal --follow --region us-west-1
   ```

3. **ALB target health check failures** - Verify targets are healthy
   ```shell
   # Check target group health
   aws elbv2 describe-target-health --target-group-arn <target-group-arn> --region us-west-1
   ```

**Resolution:**
- Ensure Google OAuth client secret is populated (see Installation Step 4)
- Verify ECS tasks are running: `aws ecs list-tasks --cluster openvpn-portal --region us-west-1`
- Check security groups allow traffic from ALB to ECS tasks

## VPN Connection Fails

**Symptoms:** OpenVPN client shows "Connection timeout" or "TLS handshake failed"

**Common causes:**
1. **Client profile outdated** - Download a fresh profile from the portal
2. **Network Load Balancer unhealthy targets** - Check ASG instance health
   ```shell
   # Check NLB target health
   aws elbv2 describe-target-health --target-group-arn <nlb-target-group-arn> --region us-west-1
   ```

3. **Security group misconfiguration** - Verify NLB security group allows port 1194
   ```shell
   # List security group rules for NLB
   aws ec2 describe-security-groups --group-ids <nlb-sg-id> --region us-west-1
   ```

4. **EC2 instances not fully bootstrapped** - Check CloudWatch Logs for bootstrap errors
   ```shell
   # View instance logs
   aws logs tail /aws/openvpn/development/openvpn --follow --region us-west-1
   ```

**Resolution:**
- Download a new OpenVPN profile from the portal
- Ensure NLB targets show "healthy" status
- Verify ASG instances have passed health checks (wait 10-15 minutes after instance launch)
- Check `/var/log/cloud-init-output.log` on EC2 instances for bootstrap errors

## Cannot Access Resources After Connecting to VPN

**Symptoms:** VPN connects successfully but cannot ping/access private resources

**Common causes:**
1. **Routes not configured** - VPN client doesn't know which traffic to route through tunnel
   ```hcl
   # Add routes in your Terraform configuration
   module "vpn" {
     routes = [
       {
         network = "10.0.0.0"
         netmask = "255.0.0.0"
       }
     ]
   }
   ```

2. **EC2 source/destination check enabled** - Prevents routing through OpenVPN instances
   - This is automatically disabled by the module
   - Verify: `aws ec2 describe-instance-attribute --instance-id <id> --attribute sourceDestCheck`

3. **Route table missing routes** - VPC route tables don't route traffic back through VPN
   - Add routes in your private subnet route tables pointing to OpenVPN instance ENIs
   - Or use VPC subnet routing (recommended for production)

4. **Security groups blocking traffic** - Destination resources may block VPN subnet (172.16.0.0/24)
   - Add security group rules to allow traffic from 172.16.0.0/24

**Resolution:**
- Configure `routes` variable to include your VPC CIDR
- Verify security groups on destination resources allow traffic from VPN subnet
- Check VPC route tables include routes back to VPN subnet

## High CPU Utilization on OpenVPN Instances

**Symptoms:** CloudWatch alarm triggers for high CPU, or autoscaling adds many instances

**Common causes:**
1. **Instance type too small** - Encryption is CPU-intensive
   - Check current instance type: `aws ec2 describe-instances --filters "Name=tag:Name,Values=openvpn"`
   - Consider upgrading from c6in.large to c6in.xlarge

2. **Many concurrent connections** - Each connection consumes CPU for encryption
   - Check active connections: `ssh ec2-user@<instance-ip> "cat /var/log/openvpn/status.log"`
   - Expected: ~10-15% CPU per 10 concurrent users on c6in.large

3. **Autoscaling threshold too low** - `autoscaling_target_cpu` may be too aggressive
   ```hcl
   # Increase target CPU percentage
   autoscaling_target_cpu = 75  # Default is 60
   ```

**Resolution:**
- Use larger instance type (var.instance_type = "c6in.xlarge")
- Adjust autoscaling threshold if instances scale too aggressively
- Monitor average CPU across ASG, not just peak instances

## EFS Mount Failures

**Symptoms:** EC2 instances fail to mount EFS, bootstrap fails

**Common causes:**
1. **Security group misconfiguration** - EFS security group doesn't allow NFS from ASG
   - Check EFS security group allows port 2049 from ASG security group

2. **EFS availability** - EFS mount targets not in all required AZs
   ```shell
   # List EFS mount targets
   aws efs describe-mount-targets --file-system-id <efs-id> --region us-west-1
   ```

3. **Network connectivity** - Instances in wrong subnets or no route to EFS
   - Verify instances are in `backend_subnet_ids`
   - Ensure subnets have route to EFS (same VPC)

**Resolution:**
- Verify EFS security group ingress rules
- Ensure EFS mount targets exist in all backend subnet AZs
- Check `/var/log/cloud-init-output.log` for specific mount errors

## Google OAuth Login Fails

**Symptoms:** Clicking "Sign in with Google" shows error or "redirect URI mismatch"

**Common causes:**
1. **Redirect URI mismatch** - Google OAuth app not configured with correct callback URL
   - Authorized redirect URI must be: `https://openvpn-portal.yourcompany.com/login/google/authorized`
   - Check in Google Cloud Console > APIs & Services > Credentials

2. **Multi-domain support not enabled** - Google OAuth app is "Internal" but users from external domains
   - If `allowed_domains` includes domains other than your primary, publish app as "External"
   - See Installation Step 4.4

3. **Domain not verified** - Users from unverified domains cannot authenticate
   - Verify all domains in `allowed_domains` are added in Google Workspace admin

**Resolution:**
- Update Google OAuth authorized redirect URIs to match your portal URL
- Publish app as "External" if supporting multiple domains
- Verify domain ownership in Google Workspace

## Instance Refresh Stuck or Failing

**Symptoms:** Terraform apply triggers instance refresh that never completes

**Common causes:**
1. **Health check grace period too short** - Instances terminated before fully bootstrapped
   ```hcl
   # Increase grace period if bootstrap takes longer
   asg_health_check_grace_period = 900  # 15 minutes (default is 600)
   ```

2. **New instances failing health checks** - Check why new instances are unhealthy
   - View bootstrap logs in CloudWatch
   - Check NLB target health status

3. **Insufficient capacity** - ASG cannot launch new instances before terminating old ones
   - Verify `asg_max_size` >= `asg_min_size * 2` to allow rolling updates

**Resolution:**
- Increase `asg_health_check_grace_period` if instances need more bootstrap time
- Check CloudWatch Logs for bootstrap failures on new instances
- Ensure `asg_max_size` allows for rolling updates (at least 2x min_size)

## Getting help

- Review the [Architecture](architecture.md) page to understand the data flow.
- Check CloudWatch logs for the portal and the OpenVPN server.
- [Contact InfraHouse](https://infrahouse.com/contact) for support.
