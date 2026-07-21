# Monitoring & Alerts

## CloudWatch Metrics

The module automatically publishes metrics to CloudWatch for monitoring VPN infrastructure health.

### Auto Scaling Group Metrics

1. **CPU Utilization** (AWS/EC2 namespace)
   - Metric: `CPUUtilization`
   - Dimensions: `AutoScalingGroupName=openvpn-<random>`
   - Alarm configured: Triggers when CPU > 80% for 5 minutes
   - Use case: Identifies when instances are overloaded

2. **Network In/Out** (AWS/EC2 namespace)
   - Metrics: `NetworkIn`, `NetworkOut`
   - Used for network-based autoscaling
   - Target: 60% of instance baseline bandwidth
   - Use case: Scales ASG based on VPN traffic volume

3. **GroupDesiredCapacity** (AWS/AutoScaling namespace)
   - Current target capacity set by autoscaling policies
   - Use case: Monitor scaling events

4. **GroupInServiceInstances** (AWS/AutoScaling namespace)
   - Number of healthy instances currently serving traffic
   - Use case: Detect capacity issues

### Network Load Balancer Metrics

1. **HealthyHostCount** (AWS/NetworkELB namespace)
   - Number of targets passing health checks
   - **Recommended alarm:** Alert when < min_size
   - Use case: Detect instance failures

2. **UnHealthyHostCount** (AWS/NetworkELB namespace)
   - Number of targets failing health checks
   - **Recommended alarm:** Alert when > 0
   - Use case: Early warning of instance problems

3. **ActiveFlowCount** (AWS/NetworkELB namespace)
   - Number of concurrent VPN connections
   - Use case: Monitor user load

4. **ProcessedBytes** (AWS/NetworkELB namespace)
   - Total bytes processed by NLB
   - Use case: Track bandwidth usage for cost optimization

### ECS Portal Metrics

1. **CPUUtilization** (AWS/ECS namespace)
   - Portal service CPU usage
   - Dimensions: `ServiceName=openvpn-portal`, `ClusterName=openvpn-portal`
   - Use case: Monitor portal performance

2. **MemoryUtilization** (AWS/ECS namespace)
   - Portal service memory usage
   - **Recommended alarm:** Alert when > 85%
   - Use case: Detect memory leaks or need for more workers

3. **RunningTaskCount** (AWS/ECS namespace)
   - Number of healthy portal tasks
   - **Recommended alarm:** Alert when < portal_task_min_count
   - Use case: Detect portal availability issues

## Setting Up Additional Alarms

### High Unhealthy Target Count
```hcl
resource "aws_cloudwatch_metric_alarm" "nlb_unhealthy_targets" {
  alarm_name          = "openvpn-unhealthy-targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/NetworkELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "Alert when NLB has unhealthy targets"

  dimensions = {
    LoadBalancer = "<load-balancer-arn-suffix>"
  }

  alarm_actions = [var.sns_topic_alarm_arn]
}
```

### Low Healthy Target Count
```hcl
resource "aws_cloudwatch_metric_alarm" "nlb_low_healthy_targets" {
  alarm_name          = "openvpn-low-healthy-targets"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/NetworkELB"
  period              = 60
  statistic           = "Average"
  threshold           = var.asg_min_size
  alarm_description   = "Alert when healthy targets below minimum"

  dimensions = {
    LoadBalancer = "<load-balancer-arn-suffix>"
  }

  alarm_actions = [var.sns_topic_alarm_arn]
}
```

### Portal Memory High
```hcl
resource "aws_cloudwatch_metric_alarm" "portal_memory_high" {
  alarm_name          = "openvpn-portal-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "Alert when portal memory usage high"

  dimensions = {
    ServiceName = "openvpn-portal"
    ClusterName = "openvpn-portal"
  }

  alarm_actions = [var.sns_topic_alarm_arn]
}
```

## CloudWatch Dashboards

Create a custom dashboard to monitor VPN health:

```shell
aws cloudwatch put-dashboard --dashboard-name OpenVPN-Monitoring \
  --dashboard-body file://openvpn-dashboard.json
```

**Example dashboard (openvpn-dashboard.json):**
```json
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          [ "AWS/NetworkELB", "HealthyHostCount", { "stat": "Average" } ],
          [ ".", "UnHealthyHostCount", { "stat": "Average" } ]
        ],
        "period": 300,
        "stat": "Average",
        "region": "us-west-1",
        "title": "NLB Target Health",
        "yAxis": {
          "left": {
            "min": 0
          }
        }
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          [ "AWS/EC2", "CPUUtilization", { "stat": "Average" } ]
        ],
        "period": 300,
        "stat": "Average",
        "region": "us-west-1",
        "title": "OpenVPN Instance CPU"
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          [ "AWS/NetworkELB", "ActiveFlowCount", { "stat": "Sum" } ]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "us-west-1",
        "title": "Active VPN Connections"
      }
    }
  ]
}
```

## Log-based Metrics

Create CloudWatch Logs metric filters to track application-level events:

### Authentication Failures
```shell
aws logs put-metric-filter \
  --log-group-name /aws/openvpn/development/openvpn \
  --filter-name AuthenticationFailures \
  --filter-pattern "[... , status=FAILED]" \
  --metric-transformations \
    metricName=AuthFailureCount,metricNamespace=OpenVPN,metricValue=1
```

### New Connections
```shell
aws logs put-metric-filter \
  --log-group-name /aws/openvpn/development/openvpn \
  --filter-name NewConnections \
  --filter-pattern "[... , event=CONNECTED]" \
  --metric-transformations \
    metricName=NewConnectionCount,metricNamespace=OpenVPN,metricValue=1
```

## Recommended Alert Configuration

For production deployments, configure these SNS notifications:

```hcl
module "vpn" {
  source = "registry.infrahouse.com/infrahouse/openvpn/aws"

  # SNS topic for instance-level alarms (high CPU, etc.)
  sns_topic_alarm_arn = aws_sns_topic.openvpn_alerts.arn

  # Email addresses for portal alarms (ECS task failures, etc.)
  alarm_emails = [
    "devops-oncall@yourcompany.com",
    "vpn-admins@yourcompany.com"
  ]
}

resource "aws_sns_topic" "openvpn_alerts" {
  name = "openvpn-infrastructure-alerts"
}

resource "aws_sns_topic_subscription" "openvpn_alerts_email" {
  topic_arn = aws_sns_topic.openvpn_alerts.arn
  protocol  = "email"
  endpoint  = "devops-oncall@yourcompany.com"
}
```

## Monitoring Checklist

- [ ] High CPU alarm configured (✅ enabled by default)
- [ ] NLB unhealthy targets alarm configured
- [ ] NLB healthy targets < min alarm configured
- [ ] Portal memory utilization alarm configured
- [ ] Portal running tasks < min alarm configured
- [ ] CloudWatch dashboard created
- [ ] SNS topic configured with email subscriptions
- [ ] Log-based metrics created for auth failures
- [ ] VPC Flow Logs enabled (external to module)
- [ ] Weekly review of CloudWatch Logs Insights queries

