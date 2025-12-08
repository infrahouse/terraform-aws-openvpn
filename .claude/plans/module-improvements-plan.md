# Terraform AWS OpenVPN Module - Implementation Plan

**Created:** 2025-12-06
**Based on Review:** `.claude/reviews/terraform-module-review.md`
**Status:** Ready for Implementation

---

## Overview

This plan addresses approved findings from the Terraform module review. 
Items are organized by priority and grouped by functional area to minimize conflicts and maximize efficiency.

**Total Approved Items:** 24
**Estimated Implementation Time:** 4-6 hours

---

## Phase 0: Module Dependencies Update ✅ COMPLETED

### 0.1 Upgrade ECS Module to v7.0.0 ✅ COMPLETED
**Priority:** High (Should do early to avoid conflicts)
**Files:** `portal.tf`, `variables.tf`, `test_data/openvpn/terraform.tfvars`
**Estimated Time:** 30 minutes
**Actual Time:** 30 minutes

**Current Version:** 5.12.0
**Target Version:** 7.0.0

**Key Changes Between Versions:**

**v6.0.0 Breaking Changes:**
- Default AMI changed from Amazon Linux 2 to Amazon Linux 2023
- AMI filter changed from `amzn2-ami-ecs-hvm-*` to `al2023-ami-ecs-hvm-*`
- Amazon Linux 2 EOL: June 30, 2025

**v7.0.0 New Features:**
- CloudWatch KMS encryption support
- Variable validation blocks added
- Website-pod upgrade to 5.12.1 with mandatory alarm_emails

**Changes Required:**
1. Update version in `portal.tf` from `5.12.0` to `7.0.0`
2. Review and test with Amazon Linux 2023 (default behavior)
3. If AL2 is required, explicitly set `ami_id` variable (not recommended - EOL soon)

**Migration Considerations:**
- Instance replacement will occur during next deployment
- New instances will use Amazon Linux 2023
- Plan for instance refresh during maintenance window
- Monitor ECS task migration

**Testing:**
- Verify portal ECS service deploys successfully
- Verify AL2023 instances come up healthy
- Test portal authentication flow
- Verify EFS mounts work on AL2023
- Check CloudWatch logs functionality
- Test container health checks

**Rollback Plan:**
- If issues occur, can temporarily pin back to 5.12.0
- Or explicitly set ami_id to AL2 AMI while investigating

**Compatibility Notes:**
- No breaking changes in module interface
- All current portal.tf parameters remain compatible
- CloudWatch KMS encryption is optional (new capability)

---

## Phase 1: Critical Fixes (Must Do)

### 1.1 Add Variable Validation ✅ COMPLETED
**Priority:** Critical
**Files:** `variables.tf`
**Estimated Time:** 45 minutes
**Actual Time:** 45 minutes

**Changes Completed:**
- ✅ Added validation to `zone_id` (Route53 zone ID format: `^Z[A-Z0-9]+$`)
- ✅ Added validation to `backend_subnet_ids` (minimum 1, valid subnet ID format)
- ✅ Added validation to `lb_subnet_ids` (minimum 1, valid subnet ID format)
- ✅ Added validation to `root_volume_size` (8 GB - 16384 GB range)
- ✅ Added validation to `environment` (Puppet naming: `^[a-z0-9_]+$`)
- ✅ Added validation to `routes` (valid IPv4 format for network and netmask)
- ✅ Added validation to `instance_type` (valid EC2 instance type format)

**Testing:**
- Test with invalid zone_id
- Test with empty subnet lists
- Test with invalid subnet IDs
- Test with out-of-range volume sizes
- Test with invalid environment values
- Test with malformed route CIDRs

---

### 1.2 Fix Module Source Inconsistency ✅ COMPLETED
**Priority:** High
**Files:** `secrets.tf`
**Estimated Time:** 5 minutes
**Actual Time:** 5 minutes

**Changes Completed:**
- ✅ Updated `module "google_client"` source from `infrahouse/secret/aws` to `registry.infrahouse.com/infrahouse/secret/aws`
- ✅ Verified all module sources are now consistent
- ✅ All modules use `registry.infrahouse.com/infrahouse/` prefix

**Affected Lines:** `secrets.tf:36`

---

## Phase 2: Security & IAM Improvements

### 2.1 Document IAM Policy Wildcard Usage ✅ COMPLETED
**Priority:** Medium
**Files:** `iam.tf`
**Estimated Time:** 5 minutes
**Actual Time:** 5 minutes

**Changes Completed:**
- ✅ Added detailed comment explaining wildcard resource requirement for `ec2:DescribeInstances`
- ✅ Referenced AWS API limitation and documentation
- ✅ Clarified that this is a read-only list operation without resource-level permission support

**Affected Lines:** `iam.tf:8-18` (added 3-line comment)

---

### 2.2 Add OpenVPN Application Logging to CloudWatch ✅ COMPLETED
**Priority:** Medium
**Files:** `openvpn-logs.tf` (new), `variables.tf`, `asg.tf`, `iam.tf`, `portal.tf`, `README.md`
**Estimated Time:** 45 minutes
**Actual Time:** 60 minutes

**Strategy Revision - Why NLB Logs Were Abandoned:**

After implementation attempt, we discovered that **NLB access logs are useless for OpenVPN**:

1. **Layer 4 Passthrough**: NLB operates at Layer 4 (TCP/UDP) and has no visibility into the TLS handshake between OpenVPN client and server
2. **No Application Data**: NLB only sees TCP connection metadata, not authentication events or user sessions
3. **Limited Value**: NLB logs would only show "TCP connection from IP X to port 1194" - already captured by VPC Flow Logs
4. **Compliance Gap**: ISO 27001 requires user authentication logs, connection duration, data transfer - none of which NLB can provide

**Revised Approach - OpenVPN Application Logs:**

Focus on capturing actual OpenVPN application logs which contain:
- Authentication events (who connected, when, from where)
- Connection duration and session details
- Bytes transferred per user
- Certificate/credential information
- Connection failures and security events

**Implementation Plan:**

1. ✅ Added unified logging variable:
   - `cloudwatch_log_retention_days` (number, default: 365)
   - Applied to both ECS portal logs and OpenVPN application logs
   - Validation for valid CloudWatch retention periods

2. ✅ Create CloudWatch Log Group for OpenVPN application logs:
   - `/aws/openvpn/${service_name}` - Main application logs
   - Retention: `var.cloudwatch_log_retention_days` (365 days default)
   - Encrypted by default (CloudWatch standard encryption)
   - Created in `openvpn-logs.tf`

3. ✅ Configure CloudWatch Logs Agent on OpenVPN EC2 instances:
   - Ship `/var/log/openvpn/openvpn.log` - Main OpenVPN logs
   - Ship `/var/log/openvpn/openvpn-status.log` - Active connections status
   - Ship `/var/log/auth.log` - System authentication (SSH, sudo)
   - Configure via user-data in ASG launch template
   - Added `amazon-cloudwatch-agent` package
   - Added CloudWatch agent configuration JSON file
   - Added `runcmd` to start CloudWatch agent service

4. ✅ Update IAM instance profile:
   - Add permissions for CloudWatch Logs (PutLogEvents, CreateLogStream, DescribeLogStreams)
   - Scope to OpenVPN log groups only

5. ✅ Update README:
   - Document logging architecture and strategy
   - Explain what logs are captured and where
   - Note that VPC Flow Logs (managed separately) capture network-level data
   - Provide guidance on querying logs for compliance/audit
   - Added comprehensive "Logging and Compliance" section

**Why This Approach is Better:**

- **Compliance-Ready**: Captures actual user authentication and session data required for ISO 27001
- **Centralized**: All logs queryable in CloudWatch Logs
- **Encrypted**: CloudWatch Logs encrypted at rest by default
- **Searchable**: CloudWatch Logs Insights for compliance queries
- **Cost-Effective**: Only pay for logs that matter, not useless NLB metadata
- **Unified Retention**: Single variable controls all CloudWatch log retention across module

**Testing:**
- ✅ Verify CloudWatch agent installation on OpenVPN instances
- ✅ Confirm logs appear in CloudWatch after VPN connection
- ✅ Test log queries for common compliance scenarios
- ✅ Validate IAM permissions are scoped correctly

---

## Phase 3: Observability & Monitoring

### 3.0
    
Fix CPU alarm using C:\Users\aleks\code\infrahouse\terraform\terraform-aws-website-pod\alarms.tf as a pattern 

### 3.1 Add CloudWatch Log Groups and Alarms ✅ APPROVED
**Priority:** Medium
**Files:** `cloudwatch.tf`, `variables.tf`
**Estimated Time:** 45 minutes

**Changes Required:**
1. Add variables:
   - `log_retention_days` (number, default: 30)
   - `cloudwatch_kms_key_arn` (string, optional)

2. Add resources:
   - `aws_cloudwatch_log_group.openvpn` - for OpenVPN server logs
   - `aws_cloudwatch_metric_alarm.unhealthy_host_count` - alert on unhealthy targets
   - `aws_cloudwatch_metric_alarm.efs_burst_credit_balance` - alert on low EFS credits

3. Update user data to ship logs to CloudWatch

**Testing:**
- Verify log groups are created
- Verify alarms trigger correctly
- Test log retention policy

---

### 3.2 Expand Module Outputs ✅ APPROVED
**Priority:** Medium
**Files:** `outputs.tf`
**Estimated Time:** 15 minutes

**Changes Required:**
Add the following outputs:
- `vpn_server_fqdn` - FQDN of OpenVPN server
- `security_group_id` - OpenVPN instance security group ID
- `efs_security_group_id` - EFS security group ID
- `efs_file_system_id` - EFS file system ID
- `efs_dns_name` - EFS DNS name
- `nlb_dns_name` - Network Load Balancer DNS name
- `openvpn_port` - OpenVPN TCP port
- `target_group_arn` - Target group ARN
- `launch_template_id` - Launch template ID
- `launch_template_latest_version` - Launch template version

**Testing:**
- Run `terraform output` and verify all values
- Use outputs in downstream modules

---

## Phase 4: Cost Optimization

### 4.1 Add EFS Lifecycle Policy ✅ APPROVED
**Priority:** Medium
**Files:** `efs-enc.tf`
**Estimated Time:** 10 minutes

**Changes Required:**
Update `aws_efs_file_system.openvpn-config-enc`:
- Add `lifecycle_policy` block for transition to IA after 30 days
- Add `lifecycle_policy` for transition back to primary storage class
- Explicitly set `performance_mode = "generalPurpose"`
- Explicitly set `throughput_mode = "bursting"`

**Testing:**
- Verify EFS is created with lifecycle policies
- Check cost impact after 30 days

---

## Phase 5: Auto Scaling Improvements

### 5.1 Optimize ASG Instance Refresh Configuration ✅ APPROVED
**Priority:** Medium
**Files:** `asg.tf`, `variables.tf`
**Estimated Time:** 20 minutes

**Changes Required:**
1. Add variables:
   - `asg_instance_refresh_max_healthy_percentage` (number, default: 110)
   - `asg_instance_refresh_checkpoint_percentages` (list(number), default: [50])
   - `asg_instance_refresh_checkpoint_delay` (number, default: 300)

2. Update `instance_refresh` block in `aws_autoscaling_group.openvpn`:
   - Add `max_healthy_percentage`
   - Add `instance_warmup` (use `asg_health_check_grace_period`)
   - Add `checkpoint_percentages`
   - Add `checkpoint_delay`
   - Add `skip_matching = false`
   - Add explicit `triggers = ["tag"]`

**Testing:**
- Trigger instance refresh
- Verify staged rollout works
- Verify checkpoint delay pauses between stages

---

### 5.2 Add Auto Scaling Policies ✅ COMPLETED
**Priority:** Medium
**Files:** `asg.tf`, `datasources.tf`, `locals.tf`, `variables.tf`
**Estimated Time:** 45 minutes
**Actual Time:** ~60 minutes

**Changes Completed:**
1. Add variables:
   - `autoscaling_target_cpu` (number, default: 60)
     - **Changed from 70% to 60%** per user preference
     - **Will be unified** across both ECS portal and VPN ASG (same value)
   - `autoscaling_target_network_percentage` (number, default: 60)
     - **New approach**: Instead of hardcoded bytes/sec, use percentage of instance type's baseline network bandwidth
     - Default: 60% of instance type's network capacity

2. Add data source in `datasources.tf`:
   - `data.aws_ec2_instance_type.openvpn` - Query instance type network characteristics
     - Queries AWS for instance type specifications
     - Provides access to `network_cards[0].baseline_bandwidth_in_gbps`
     - Real-time data from AWS API, no hardcoded values to maintain

3. Add local value in `locals.tf`:
   - `autoscaling_target_network_in` - Calculated value based on instance type
     - Formula: `(data.aws_ec2_instance_type.openvpn.network_cards[0].baseline_bandwidth_in_gbps * 1000 * var.autoscaling_target_network_percentage / 100) * 1000000`
     - Converts Gbps → Mbps → bytes/sec and applies percentage
     - Uses real AWS data from ec2_instance_type data source

3. Add resources:
   - `aws_autoscaling_policy.cpu_target_tracking` - CPU-based scaling (60% target)
   - `aws_autoscaling_policy.network_target_tracking` - Network-based scaling (calculated target)

**Rationale for Network Bandwidth Approach:**
- **Problem with hardcoded 50MB/s**: Not instance-type aware; too low for large instances, too high for small ones
- **Why use aws_ec2_instance_type data source**:
  - Provides real-time network bandwidth data directly from AWS API
  - No hardcoded lookup tables to maintain
  - Automatically supports new instance types
  - AWS provides `baseline_bandwidth_in_gbps` for all production instance types
  - If an instance type doesn't provide network bandwidth data, it may not be suitable for VPN workloads
- **Benefits of percentage-based approach**:
  - Scales automatically with instance type selection
  - User can adjust percentage threshold via variable
  - Zero maintenance - AWS provides the data
  - Self-documenting - uses official AWS instance type specifications

**Implementation Example:**
```hcl
# datasources.tf
data "aws_ec2_instance_type" "openvpn" {
  instance_type = var.instance_type
}

# locals.tf
locals {
  # Calculate network autoscaling target based on instance type
  # Formula: (baseline_gbps * 1000 to get Mbps * percentage / 100) * 1000000 to get bytes/sec
  autoscaling_target_network_in = (
    data.aws_ec2_instance_type.openvpn.network_cards[0].baseline_bandwidth_in_gbps * 1000
    * var.autoscaling_target_network_percentage / 100
  ) * 1000000
}
```

**Example Values:**
- c6in.large (25 Gbps baseline) @ 60% = 15 Gbps = 15,000,000,000 bytes/sec
- t3a.small (5 Gbps baseline) @ 60% = 3 Gbps = 3,000,000,000 bytes/sec
- m7i.large (12.5 Gbps baseline) @ 60% = 7.5 Gbps = 7,500,000,000 bytes/sec

**ECS Portal Autoscaling:**
- Update existing ECS portal autoscaling target to use same `var.autoscaling_target_cpu` (60%)
- Keeps CPU threshold unified across both services

**Testing:**
- Test with default values (60% CPU, 60% of network bandwidth)
- Test with different instance types (verify network target adjusts)
- Generate CPU load and verify scaling
- Generate network traffic and verify scaling
- Verify scale-down works
- Test with custom variable values

---

## Phase 6: Documentation & Validation

### 6.1 Improve Variable Descriptions ✅ COMPLETED
**Priority:** Low
**Files:** `variables.tf`
**Estimated Time:** 30 minutes
**Actual Time:** ~45 minutes

**Changes Completed:**
Used HEREDOC format for detailed descriptions on these variables:
- ✅ `service_name` - DNS usage, resource naming, CloudWatch log paths
- ✅ `zone_id` - Route53 integration and automatic domain addition
- ✅ `backend_subnet_ids` - Requirements, HA considerations, default impacts
- ✅ `lb_subnet_ids` - NLB requirements, public subnet needs
- ✅ `routes` - VPN route push examples with format details
- ✅ `allowed_domains` - Google OAuth domain authentication with multi-domain
- ✅ `key_pair_name` - ⚠️ SECURITY WARNING added with SSH best practices
- ✅ `asg_health_check_grace_period` - 10-minute bootstrap process breakdown
- ✅ `portal_workers_count` - Worker sizing formula, instance type recommendations
- ✅ `instance_type` - BONUS: Comprehensive guide with cost comparison, network performance

**Testing:**
- ✅ All descriptions use HEREDOC format
- ✅ Security warnings prominently displayed
- ✅ Examples provided for complex variables
- ✅ When to increase/decrease guidance included

---

### 6.2 Add Data Source Validation ❌ SKIPPED
**Priority:** Low
**Files:** `datasources.tf`
**Estimated Time:** N/A

**Reason for Skipping:**
- Terraform and AWS API already provide clear error messages when data sources fail
- Postconditions add verbosity without significant value
- Variable validation (Phase 1.1) already catches format errors before API calls
- `data.aws_internet_gateway.current` was unused and has been removed

**Changes Made:**
- ✅ Removed unused `data.aws_internet_gateway.current` data source from `datasources.tf`

**Rationale:**
Data source validation through postconditions is redundant. When a data source query fails (e.g., invalid zone_id), Terraform naturally fails with clear AWS API error messages. Adding postconditions would only add maintenance burden without improving user experience.

---

### 6.3 Adjust ASG Health Check Grace Period ❌ SKIPPED
**Priority:** Low
**Files:** `variables.tf`
**Estimated Time:** N/A

**Reason for Skipping:**
- User explicitly requested to skip this phase
- Current 600 second (10 minute) grace period is adequate for bootstrap process
- Variable description already enhanced in Phase 6.1 with HEREDOC format explaining when to adjust

**No changes made.**

---

### 6.4 Optimize Portal Worker Count ❌ SKIPPED
**Priority:** Low
**Files:** `variables.tf`, `portal.tf`, `locals.tf`
**Estimated Time:** N/A

**Reason for Skipping:**
- Comprehensive variable documentation with worker sizing guidance already added in Phase 6.1
- Current hardcoded default (4 workers) with manual override is simpler and more predictable
- Auto-calculation would be complex: portal runs on ECS (Fargate or EC2), making instance type detection non-trivial
- Container resources (`container_cpu = 400`, `container_memory = 200`) are more relevant than host instance type
- Users have clear guidance via HEREDOC description including formula: (2 x CPU cores) + 1
- Low ROI: Auto-calculation adds complexity without significant benefit

**What's Already Done (Phase 6.1):**
- ✅ Comprehensive HEREDOC description with recommended worker counts by instance type
- ✅ Formula documented: (2 x CPU cores) + 1
- ✅ Memory/CPU per worker metrics provided
- ✅ When to increase/decrease guidance included
- ✅ Clear default: 4 workers (suitable for t3.small with moderate user load)

**No changes made.**

---

## Phase 7: Resource Management

### 7.1 Add EFS Backup Strategy ✅ COMPLETED
**Priority:** Medium
**Files:** New file `efs-backup.tf`, `variables.tf`
**Estimated Time:** 40 minutes
**Actual Time:** ~35 minutes

**Changes Completed:**
1. ✅ Added variables to `variables.tf`:
   - `enable_efs_backup` (bool, default: true) - Enable/disable EFS backups
   - `efs_backup_schedule` (string, default: "cron(0 2 * * ? *)") - Daily at 2 AM UTC
   - `efs_backup_retention_days` (number, default: 30) - Retention period with validation

2. ✅ Created `efs-backup.tf` with resources:
   - `aws_backup_vault.efs` - Backup vault for storing EFS backups
   - `aws_backup_plan.efs` - Daily backup plan with lifecycle management
   - `aws_backup_selection.efs` - Selects EFS file system for backup
   - `aws_iam_role.backup` - IAM role for AWS Backup service with random suffix
   - `aws_iam_role_policy_attachment.backup_efs` - AWS managed backup policy
   - `aws_iam_role_policy_attachment.backup_restore` - AWS managed restore policy

**Implementation Notes:**
- All resources use `count` based on `var.enable_efs_backup` for opt-in/opt-out
- IAM role uses `random_string.role-suffix` for unique naming (follows module pattern)
- Backup vault includes proper tagging with `Name` tag and module tags
- Continuous backup disabled (set to false) - uses scheduled backups only
- Lifecycle policy configured with `delete_after` for retention management

**Testing:**
- Verify backup vault is created
- Trigger manual backup
- Test restore from backup
- Verify retention policy

---

### 7.2 Add Missing Name Tags ✅ COMPLETED
**Priority:** Low
**Files:** `nlb.tf`, `iam-openvpn-portal.tf`, `cloudwatch.tf`
**Estimated Time:** 15 minutes
**Actual Time:** ~10 minutes

**Changes Completed:**
✅ Added explicit `Name` tag to resources using `merge()` with `local.default_module_tags`:
- `aws_lb_target_group.openvpn` - Added Name: "${var.service_name}-target-group"
- `aws_lb_listener.openvpn` - Added Name: "${var.service_name}-listener"
- `aws_iam_role.openvpn_portal_role` - Added Name: "${var.service_name}-portal-task-role"
- `aws_cloudwatch_metric_alarm.cpu_utilization_alarm` - Added Name: "${var.service_name}-cpu-alarm"

**Implementation Notes:**
- All Name tags follow consistent naming pattern: `${var.service_name}-<resource-type>`
- Tags merged with existing `local.default_module_tags` to preserve module tagging
- NLB already has proper tags via `local.default_module_tags`
- EFS backup IAM role already includes Name tag (added in Phase 7.1)

**Testing:**
- Verify Name tags appear in AWS console
- Verify tags follow naming convention

---

## Phase 8: Testing & Quality Assurance

### 8.1 Add Security Scanning to CI/CD ✅ COMPLETED
**Priority:** Medium
**Files:** `.github/workflows/terraform-CI.yml`, `.checkov.yml`, `requirements.txt`
**Estimated Time:** 20 minutes
**Actual Time:** ~90 minutes (including skip rule documentation and security group fixes)

**Changes Completed:**
1. ✅ Added Checkov scan step to CI workflow
   - Installs checkov via pip
   - Runs with `.checkov.yml` configuration
   - Scans all Terraform files
   - Reports findings in CI output

2. ✅ Created `.checkov.yml` configuration with 9 documented skip rules:
   - CKV_TF_1: Private registry versioning
   - CKV_AWS_166: Backup vault AWS-managed encryption
   - CKV_AWS_150: NLB deletion protection
   - CKV_AWS_91: NLB access logs
   - CKV_AWS_158: CloudWatch Logs encryption
   - CKV_AWS_277: ICMP on NLB
   - CKV_AWS_163: ECR image scanning (AWS Inspector preferred)
   - CKV_AWS_136: Test ECR encryption
   - CKV_AWS_51: Test ECR immutable tags

3. ✅ Added `checkov ~= 3.2` to `requirements.txt`

4. ❌ **Skipped tfsec** - Deprecated tool, replaced by Trivy
   - tfsec team recommends migrating to Trivy
   - Checkov provides comprehensive coverage
   - No need for redundant scanners

**Security Fixes Made:**
- Fixed EFS ICMP: Changed from 0.0.0.0/0 to VPC CIDR
- Added descriptions to all security group rules
- Refactored security groups (NLB vs ASG separation)

**Testing:**
- ✅ Checkov runs successfully locally with `.checkov.yml`
- ✅ All skip rules documented with clear rationale
- ✅ No blocking security issues remain

---

### 8.2 Enhance README Documentation ✅ APPROVED
**Priority:** Low
**Files:** `README.md`, `.terraform-docs.yml`
**Estimated Time:** 45 minutes

**Changes Required:**
Add new sections to README:
1. **Troubleshooting** - common issues and solutions
2. **Security Best Practices** - recommendations
3. **Cost Optimization** - tips for reducing costs
4. **Monitoring & Alerts** - how to set up monitoring
5. **Testing Locally** - developer workflow

Update `.terraform-docs.yml` if needed for new sections.

**Testing:**
- Review README for completeness
- Test any code examples in README
- Verify links work

---

## Phase 9: Optional Enhancements

### 9.1 Add WAF Integration for Portal ✅ APPROVED
**Priority:** Low
**Files:** `portal.tf`, `variables.tf`
**Estimated Time:** 20 minutes

**Changes Required:**
1. Add variables:
   - `enable_portal_waf` (bool, default: false)
   - `portal_waf_acl_arn` (string, default: null)

2. Update portal module call:
   - Pass WAF ACL ARN to module if provided
   - Document WAF requirements

**Testing:**
- Deploy with WAF enabled
- Verify WAF rules apply to portal
- Test portal functionality with WAF

---

## Implementation Order & Dependencies

### Recommended Sequence:
0. **Phase 0** (ECS Module Upgrade) - Do FIRST to avoid conflicts
1. **Phase 1** (Critical Fixes) - Do second, blocks other work
2. **Phase 2** (Security) - High priority, independent
3. **Phase 3** (Observability) - Medium priority, independent
4. **Phase 4** (Cost Optimization) - Quick wins, independent
5. **Phase 5** (Auto Scaling) - Depends on Phase 1 (variables)
6. **Phase 7** (Resource Management) - Independent
7. **Phase 6** (Documentation) - Do after functional changes
8. **Phase 8** (Testing) - Do near end to validate all changes
9. **Phase 9** (Optional) - Do last or defer

### Dependency Graph:
```
Phase 0 (ECS Upgrade) → Should be done first (independent but foundational)
Phase 1 (Variables) → Phase 5 (ASG), Phase 6 (Docs)
Phase 2 (Security) → Independent
Phase 3 (Monitoring) → Independent
Phase 4 (Cost) → Independent
Phase 7 (Resources) → Independent
Phase 6 (Docs) → Depends on all functional changes
Phase 8 (Testing) → Depends on all changes
Phase 9 (Optional) → Independent
```

---

## Testing Strategy

### Per-Phase Testing:
Each phase should be tested individually before moving to the next:
1. Run `terraform fmt`
2. Run `terraform validate`
3. Run `terraform plan` with test data
4. Run `terraform apply` in test environment
5. Verify functionality
6. Run module tests: `make test-keep`
7. Clean up if needed: `terraform destroy`

### Integration Testing:
After all phases complete:
1. Full `terraform plan` and `apply`
2. Run complete test suite: `make test-clean`
3. Test against both AWS provider v5 and v6
4. Verify outputs work in downstream modules
5. Test upgrade path from current version

### Security Testing:
- Run Checkov scan
- Run tfsec scan
- Manual security review of IAM policies
- Verify encryption at rest and in transit

### Performance Testing:
- Load test VPN connections
- Verify auto-scaling works
- Check EFS performance
- Monitor CloudWatch metrics

---

## Risk Assessment

### Low Risk Changes:
- Adding outputs
- Adding variable descriptions
- Adding comments
- Adding tags
- Documentation updates

### Medium Risk Changes:
- Adding variable validation (may break existing uses)
- Changing default values
- Adding lifecycle policies
- Adding CloudWatch alarms
- Modifying ASG configuration

### High Risk Changes:
- None identified (all changes are additive or cosmetic)

### Mitigation Strategies:
1. **Variable Validation:** Use permissive regex patterns initially
2. **Default Values:** Don't change existing defaults unless critical
3. **New Features:** Make all new features opt-in (disabled by default)
4. **Breaking Changes:** Version bump to 5.0.0 if any breaking changes
5. **Testing:** Comprehensive testing before release

---

## Rollback Plan

If issues are discovered after deployment:
1. Identify problematic phase
2. Revert specific commit or phase
3. Keep beneficial changes from other phases
4. Re-test after revert
5. Fix issue and re-apply

**Git Strategy:**
- Use feature branches for each phase
- Tag each phase completion
- Merge to main only after testing
- Use conventional commits for easy revert

---

## Success Criteria

### Phase Completion:
- [ ] All code changes implemented
- [ ] All tests pass (both AWS provider v5 and v6)
- [ ] Terraform fmt, validate succeed
- [ ] Documentation updated
- [ ] Security scans pass (or issues documented)
- [ ] No breaking changes (or documented in CHANGELOG)

### Final Acceptance:
- [ ] Module grade improved from B+ to A-/A
- [ ] All critical issues resolved
- [ ] All approved security concerns addressed
- [ ] All approved important improvements implemented
- [ ] Testing coverage increased
- [ ] Documentation comprehensive
- [ ] Ready for production use

---

## Timeline Estimate

### Optimistic (Developer Experienced with Module):
- Phase 0: 30 minutes
- Phase 1: 1 hour
- Phase 2: 30 minutes
- Phase 3: 1 hour
- Phase 4: 15 minutes
- Phase 5: 1 hour
- Phase 6: 1 hour
- Phase 7: 1 hour
- Phase 8: 1 hour
- Phase 9: 30 minutes
- **Total: ~8.5 hours**

### Realistic (Including Testing):
- Implementation: 8.5 hours
- Testing: 4 hours
- Documentation: 2 hours
- Review & Fixes: 2 hours
- **Total: 16.5 hours (~2 days)**

### With Contingency:
- Add 50% buffer: **25 hours (~3 days)**

---

## Next Steps

1. **Review this plan** and adjust priorities if needed
2. **Approve phases** to implement
3. **Create feature branch** from main
4. **Start with Phase 1** (critical fixes)
5. **Implement phase by phase** with testing
6. **Create PR** when complete
7. **Conduct final review** before merge
8. **Tag release** with appropriate version bump

---

## Notes

- All changes are **backwards compatible** except variable validation
- Consider **version bump to 5.0.0** if variable validation could break existing deployments
- Alternative: Make validation **opt-in** with a variable flag initially
- **Skipped items** from review are documented but not in this plan
- Items marked with 💬 DISCUSS were excluded pending further discussion
- Focus is on **production readiness** and **InfraHouse compliance**

---

**Plan Status:** ✅ Ready for Implementation
**Approval Required:** Yes - Please review and approve before starting
