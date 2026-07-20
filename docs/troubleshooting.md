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
4. See [Google OAuth setup](getting-started.md#google-oauth-setup).

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

## Google directory revocation (WIF) fails

Run `sudo /opt/openvpn-wif/verify-wif.sh` on an OpenVPN instance. It tests the
chain one link at a time, so the first failing tier tells you where to look.

| Symptom | Cause / fix |
|---------|-------------|
| Tier 1 fails, or the ARN does not match | The instance is not using the role the WIF provider is locked to. Compare with the provider's `attribute_condition`. |
| Tier 2 fails | Federation rejected — usually the AWS role ARN does not match the attribute condition, or the pool/provider is not `ACTIVE`. |
| Tier 3 fails | The `workloadIdentityUser` / `serviceAccountTokenCreator` bindings on the service account are missing. |
| Tier 4: `unauthorized_client` | The subject is valid, but the SA's client ID is not authorized for the scope. Complete [domain-wide delegation](configuration.md#required-manual-step-domain-wide-delegation). Just authorized it? Wait a few minutes and re-run — propagation is not instant. |
| Tier 4: `invalid_grant: Invalid email or User ID` | Google cannot find the subject: `google_directory_admin_subject` is not a real, active user in that Workspace. |
| `google-auth is installed but too old` | The distro `python3-google-auth` (1.5.x) lacks `external_account` and `impersonated_credentials`. Install `google-auth >= 2` and `google-api-python-client`. |

The script is read-only — it never installs or changes anything.

## Getting help

- Review the [Architecture](architecture.md) page to understand the data flow.
- Check CloudWatch logs for the portal and the OpenVPN server.
- [Contact InfraHouse](https://infrahouse.com/contact) for support.
