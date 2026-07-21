# Security Best Practices

## Network Security

1. **Restrict SSH Access**
   - Limit SSH security group rules to specific IP ranges (not 0.0.0.0/0)
   - Consider using AWS Systems Manager Session Manager instead of SSH
   - Rotate SSH keys regularly

2. **Enable VPC Flow Logs**
   - Capture network traffic metadata for security monitoring
   - Send to CloudWatch Logs for querying
   - Also export to S3 for long-term retention

3. **Use Private Subnets for Backend**
   - Deploy OpenVPN instances in private subnets (`backend_subnet_ids`)
   - Use NAT Gateway for outbound internet access
   - Only NLB should be in public subnets (`lb_subnet_ids`)

4. **Enable AWS GuardDuty**
   - Monitors for malicious activity and unauthorized behavior
   - Detects compromised instances
   - Analyzes VPC Flow Logs and CloudTrail events

## Access Control

1. **Implement Least Privilege IAM**
   - Limit `google_oauth_client_writer` role to specific users/groups
   - Use AWS SSO instead of IAM users for human access
   - Regularly review IAM policies attached to instance profiles

2. **Enable MFA for Google OAuth**
   - Enforce MFA in Google Workspace for all VPN users
   - Set up security policies requiring MFA for external access

3. **Limit Allowed Domains**
   - Only add trusted domains to `allowed_domains`
   - Review the list quarterly
   - Remove domains when partnerships end

4. **Use Short-Lived Credentials**
   - Set up certificate rotation via EFS lifecycle
   - Configure OpenVPN to expire idle sessions
   - Consider implementing certificate revocation lists (CRL)

## Data Protection

1. **Enable EFS Backup**
   ```hcl
   enable_efs_backup = true
   efs_backup_retention_days = 365
   ```

2. **Use CMK for EFS Encryption** (Optional)
   - EFS already uses AWS-managed encryption by default
   - For stricter compliance, use customer-managed KMS key
   - Enables key rotation and access logging

3. **Encrypt CloudWatch Logs** (Optional)
   - Logs use AWS-managed encryption by default
   - For stricter compliance, configure log group KMS encryption

4. **Secure Secrets Management**
   - Never commit Google OAuth credentials to Git
   - Use AWS Secrets Manager for all sensitive data
   - Enable secret rotation where possible

## Monitoring and Auditing

1. **Enable CloudTrail**
   - Log all AWS API calls
   - Monitor for unauthorized infrastructure changes
   - Set up alerts for security group modifications

2. **Configure CloudWatch Alarms**
   - High CPU utilization (already configured)
   - Authentication failures
   - Unusual connection patterns
   - EFS mount failures

3. **Regular Security Audits**
   - Review CloudWatch Logs for failed login attempts
   - Monitor active VPN sessions
   - Check for security group changes
   - Review IAM access patterns

4. **Incident Response Plan**
   - Document procedure for revoking user access
   - Plan for rotating Google OAuth credentials
   - Test EFS restore process
   - Maintain runbook for common security events

## Compliance Considerations

1. **ISO 27001 / SOC 2**
   - Enable all logging (VPC Flow Logs, CloudWatch, CloudTrail)
   - Set log retention to 365 days minimum
   - Implement regular access reviews
   - Document security controls

2. **HIPAA / PCI DSS**
   - Use customer-managed KMS keys for encryption
   - Enable detailed audit logging
   - Implement network segmentation
   - Regular vulnerability scanning

3. **GDPR**
   - Document data flows through VPN
   - Implement user access controls
   - Enable log anonymization if needed
   - Data retention policies for logs


# Logging and Compliance

The module provides comprehensive logging for audit trail and ISO 27001 compliance requirements.

## Logging Architecture

The module captures three layers of logging:

### 1. OpenVPN Application Logs (Recommended - In Progress)
**What it captures:**
- User authentication events (who connected, when, from where)
- Connection duration and session details
- Bytes transferred per user
- Certificate/credential validation
- Connection failures and security events

**Where:**
- CloudWatch Logs: `/aws/openvpn/<service_name>`
- Retention: Configurable via `cloudwatch_log_retention_days` (default: 365 days)

**Why it matters:**
This is your primary audit trail for **user access control** - required for ISO 27001 compliance. These logs prove who accessed your infrastructure and when.

### 2. ECS Portal Logs (Configured)
**What it captures:**
- Portal application logs
- User authentication via Google OAuth
- Profile generation events
- Application errors

**Where:**
- CloudWatch Logs: Managed by ECS module
- Retention: Controlled by `cloudwatch_log_retention_days` variable

### 3. VPC Flow Logs (External - Recommended)
**What it captures:**
- Network-level connection metadata
- Source/destination IPs and ports
- Bytes transferred
- Accept/reject decisions

**Where:**
- Managed separately via VPC configuration
- Recommend sending to both CloudWatch Logs (for queries) and S3 (for long-term retention)

**Why it matters:**
Network-level audit trail for compliance and security incident investigation.

## Why NLB Access Logs Are NOT Included

Network Load Balancer (NLB) access logs are **intentionally not configured** for this module because:

1. **Layer 4 Passthrough**: NLB operates at Layer 4 (TCP/UDP) and cannot see into the TLS tunnel between OpenVPN client and server
2. **No Application Visibility**: NLB only sees "TCP connection from IP X to port 1194" - no user identity, no authentication events
3. **Redundant Data**: VPC Flow Logs already capture this network metadata
4. **Compliance Gap**: ISO 27001 requires user access logs, which NLB cannot provide

**Bottom line:** For OpenVPN, NLB logs provide no additional value over VPC Flow Logs.

## Querying Logs for Compliance

Use CloudWatch Logs Insights to query OpenVPN logs:

```
# Find all connections from a specific user
fields @timestamp, @message
| filter @message like /user@example.com/
| sort @timestamp desc

# Find all authentication failures
fields @timestamp, @message
| filter @message like /AUTH.*FAILED/
| sort @timestamp desc

# Calculate connection duration for a user
fields @timestamp, @message
| filter @message like /CONNECTED/ or @message like /DISCONNECTED/
| stats count() by bin(5m)
```

## Log Retention and Costs

- **Default retention**: 365 days (1 year)
- **Configurable via**: `cloudwatch_log_retention_days` variable
- **Valid values**: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653, or 0 (never expire)
- **Cost optimization**: Set to 90 days for cost savings if long-term retention not required

## Compliance Recommendations

For **ISO 27001** or other compliance frameworks:

1. ✅ **Enable VPC Flow Logs** (if not already enabled)
2. ✅ **Configure log retention** according to your compliance requirements (365 days default)
3. ✅ **Set up CloudWatch alarms** for authentication failures
4. ✅ **Regular log reviews** using CloudWatch Logs Insights
5. ✅ **Export to S3** for long-term archival (if retention > 3653 days required)

