# Cost Optimization

## Compute Costs

1. **Right-size Instance Types**
   - Monitor CPU and network utilization in CloudWatch
   - If average CPU < 30%, consider smaller instance type
   - If network consistently high, upgrade to network-optimized instance

   ```hcl
   # Current cost: c6in.large ~$82/month
   # Downgrade option: t3a.small ~$15/month (dev/test only)
   # Upgrade option: c6in.xlarge ~$164/month (high load)
   instance_type = "c6in.large"
   ```

2. **Use Spot Instances for Non-Production**
   - Save up to 70% on compute costs
   - Suitable for dev/test environments
   - Maintain minimum on-demand capacity for stability

   ```hcl
   # Request spot instances with 2 on-demand base
   on_demand_base_capacity = 2
   asg_min_size = 2
   asg_max_size = 6
   ```

3. **Optimize Auto Scaling Thresholds**
   - Increase target CPU to reduce over-provisioning
   - Adjust network threshold based on actual usage patterns

   ```hcl
   autoscaling_target_cpu = 70  # Default: 60
   autoscaling_target_network_percentage = 70  # Default: 60
   ```

4. **Schedule Scale-Down for Off-Hours**
   - For environments with predictable usage (e.g., office hours only)
   - Use AWS Auto Scaling scheduled actions
   - Reduce `asg_min_size` during nights/weekends

## Storage Costs

1. **Optimize EFS Lifecycle Policies**
   - EFS Standard costs $0.30/GB-month
   - EFS Infrequent Access costs $0.025/GB-month (90% savings)
   - Set up lifecycle policy to move old certificates to IA storage

   ```shell
   # Add lifecycle policy to move files >30 days old to IA
   aws efs put-lifecycle-configuration --file-system-id <fs-id> \
     --lifecycle-policies TransitionToIA=AFTER_30_DAYS
   ```

2. **Optimize CloudWatch Logs Retention**
   - 365 days retention: ~$0.50/GB ingestion + $0.03/GB storage
   - Consider 90 days for non-compliance environments

   ```hcl
   cloudwatch_log_retention_days = 90  # Default: 365
   ```

3. **Optimize EFS Backups**
   - AWS Backup costs $0.05/GB-month (warm storage)
   - Consider shorter retention for non-critical environments

   ```hcl
   efs_backup_retention_days = 30  # Default: 365 (compliance)
   ```

## Network Costs

1. **Minimize Cross-AZ Traffic**
   - Deploy NLB and ASG in same availability zones
   - Cross-AZ data transfer costs $0.01/GB
   - Use `lb_subnet_ids` and `backend_subnet_ids` in matching AZs

2. **Optimize VPN Routes**
   - Only push necessary routes through VPN tunnel
   - Avoid routing internet traffic through VPN (unless required)
   - Use split-tunnel configuration

   ```hcl
   # Only route private networks through VPN
   routes = [
     {
       network = "10.0.0.0"
       netmask = "255.0.0.0"
     }
   ]
   # Internet traffic goes directly from client
   ```

3. **Use VPC Endpoints**
   - Reduce NAT Gateway costs for AWS service access
   - S3 and DynamoDB endpoints are free
   - Interface endpoints cost $0.01/hour (~$7/month)

## Portal Costs

1. **Optimize ECS Task Count**
   - Monitor portal usage patterns
   - For small teams (<20 users), single task may suffice

   ```hcl
   portal_task_min_count = 1  # Default: number of backend subnets
   portal_task_max_count = 2  # Default: min_count + 1
   ```

2. **Right-size Portal Instance Type**
   - Monitor memory and CPU usage in ECS metrics
   - Default t3.small is suitable for <50 users

   ```hcl
   portal_instance_type = "t3.small"  # ~$15/month
   # Alternative: t3.nano for very small teams (~$4/month)
   ```

3. **Optimize Worker Count**
   - Reduce workers if portal sees light usage
   - Monitor response times to ensure adequate capacity

   ```hcl
   portal_workers_count = 2  # Default: 4
   ```

## Overall Cost Reduction Tips

1. **Use AWS Cost Explorer**
   - Tag all resources with environment/project tags
   - Filter costs by tag to identify expensive resources
   - Set up budget alerts

2. **Dev/Test Environment Optimization**
   - Use smaller instance types
   - Enable spot instances
   - Shorter log retention (30 days)
   - Reduce backup retention (7 days)
   - Scale down to 0 instances during off-hours

3. **Production Cost Monitoring**
   - Set up CloudWatch billing alarms
   - Monthly cost review
   - Identify unused resources (idle load balancers, unattached EBS volumes)

**Example Cost Breakdown (us-east-1):**
- OpenVPN instances (2x c6in.large): ~$164/month
- NLB: ~$18/month (base) + $0.006/GB processed
- EFS: ~$3/month (10 GB) + lifecycle savings
- Portal (1x t3.small ECS task): ~$15/month
- CloudWatch Logs: ~$5/month (moderate usage)
- EFS Backups: ~$0.50/month (10 GB)
- **Total: ~$205-215/month** (small deployment, 2 instances, <100 users)

