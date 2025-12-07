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

### 5.2 Add Auto Scaling Policies ✅ APPROVED
**Priority:** Medium
**Files:** `asg.tf`, `variables.tf`
**Estimated Time:** 30 minutes

**Changes Required:**
1. Add variables:
   - `enable_autoscaling` (bool, default: false)
   - `autoscaling_target_cpu` (number, default: 70)
   - `autoscaling_target_network_in` (number, default: 50000000) # 50 MB/s

2. Add resources:
   - `aws_autoscaling_policy.cpu_target_tracking` - CPU-based scaling
   - `aws_autoscaling_policy.network_target_tracking` - Network-based scaling

**Testing:**
- Generate CPU load and verify scaling
- Generate network traffic and verify scaling
- Verify scale-down works

---

## Phase 6: Documentation & Validation

### 6.1 Improve Variable Descriptions ✅ APPROVED
**Priority:** Low
**Files:** `variables.tf`
**Estimated Time:** 30 minutes

**Changes Required:**
Use HEREDOC format for detailed descriptions on these variables:
- `service_name`
- `zone_id`
- `backend_subnet_ids`
- `lb_subnet_ids`
- `routes`
- `allowed_domains`
- `key_pair_name` (add security warning)
- `asg_health_check_grace_period` (explain why it's long)
- `portal_workers_count` (add instance type guidance)

**Testing:**
- Run `terraform-docs` and verify output
- Review generated README

---

### 6.2 Add Data Source Validation ✅ APPROVED
**Priority:** Low
**Files:** `datasources.tf`
**Estimated Time:** 15 minutes

**Changes Required:**
Add `postcondition` lifecycle blocks to:
- `data.aws_route53_zone.current` - verify zone exists
- `data.aws_internet_gateway.current` - verify IGW exists
- `data.aws_vpc.selected` - verify VPC exists

**Testing:**
- Test with invalid zone_id
- Test with VPC without IGW
- Verify error messages are helpful

---

### 6.3 Adjust ASG Health Check Grace Period ✅ APPROVED
**Priority:** Low
**Files:** `variables.tf`
**Estimated Time:** 5 minutes

**Changes Required:**
- Update `asg_health_check_grace_period` default from 600 to 420 (7 minutes)
- Enhance description explaining when to increase this value
- Add comment about typical bootstrap time

**Testing:**
- Verify instances become healthy within grace period
- Test with intentionally broken user data (should fail within grace period)

---

### 6.4 Optimize Portal Worker Count ✅ APPROVED
**Priority:** Low
**Files:** `variables.tf`, `portal.tf`, `locals.tf`
**Estimated Time:** 20 minutes

**Changes Required:**
1. Add `locals.worker_recommendations` map (instance type -> worker count)
2. Update `portal_workers_count` variable:
   - Change type to `number` with `default = null`
   - Add description explaining auto-calculation
   - Document manual override capability

3. Update portal configuration to use:
   - `var.portal_workers_count != null ? var.portal_workers_count : local.default_workers`

**Testing:**
- Test with default (null) - verify auto-calculation
- Test with explicit value - verify override works
- Test with various instance types

---

## Phase 7: Resource Management

### 7.1 Add EFS Backup Strategy ✅ APPROVED
**Priority:** Medium
**Files:** New file `efs-backup.tf`, `variables.tf`, `iam.tf`
**Estimated Time:** 40 minutes

**Changes Required:**
1. Add variables:
   - `enable_efs_backup` (bool, default: true)
   - `efs_backup_schedule` (string, default: "cron(0 2 * * ? *)")
   - `efs_backup_retention_days` (number, default: 30)

2. Create resources:
   - `aws_backup_vault.efs` - backup vault with KMS encryption
   - `aws_backup_plan.efs` - daily backup plan
   - `aws_backup_selection.efs` - select EFS file system
   - `aws_iam_role.backup` - IAM role for AWS Backup
   - `aws_iam_role_policy_attachment.backup` - attach AWS managed policies

**Testing:**
- Verify backup vault is created
- Trigger manual backup
- Test restore from backup
- Verify retention policy

---

### 7.2 Add Missing Name Tags ✅ APPROVED
**Priority:** Low
**Files:** `nlb.tf`, `iam.tf`, `cloudwatch.tf`
**Estimated Time:** 15 minutes

**Changes Required:**
Add explicit `Name` tag to:
- `aws_lb_target_group.openvpn`
- `aws_lb_listener.openvpn`
- IAM roles (if not already tagged)
- CloudWatch alarms

**Testing:**
- Verify Name tags appear in AWS console
- Verify tags follow naming convention

---

## Phase 8: Testing & Quality Assurance

### 8.1 Add Security Scanning to CI/CD ✅ APPROVED
**Priority:** Medium
**Files:** `.github/workflows/terraform-CI.yml`
**Estimated Time:** 20 minutes

**Changes Required:**
Add to CI workflow:
1. Checkov scan step:
   - Install checkov
   - Run scan on all Terraform files
   - Use soft-fail mode initially

2. tfsec scan step:
   - Use tfsec-action
   - Configure soft-fail

**Testing:**
- Create PR and verify scans run
- Review scan output
- Address any critical findings

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
