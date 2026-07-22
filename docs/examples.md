# Examples

Common deployment patterns. All examples assume the two providers from
[Getting Started](getting-started.md#provider-configuration) are configured.

## Minimal production deployment

```hcl
module "openvpn" {
  source  = "registry.infrahouse.com/infrahouse/openvpn/aws"
  version = "8.0.0"
  providers = {
    aws     = aws
    aws.dns = aws.dns
    google  = google
  }

  environment                = "production"
  alarm_emails               = ["alerts@example.com"]
  backend_subnet_ids         = var.private_subnet_ids
  lb_subnet_ids              = var.public_subnet_ids
  zone_id                    = data.aws_route53_zone.this.zone_id
  google_oauth_client_writer = data.aws_iam_role.admin.arn
  replication_region         = "us-east-1"
}
```

## Pushing routes to clients

Give VPN clients access to private CIDRs by pushing routes:

```hcl
module "openvpn" {
  # ...required inputs...

  routes = [
    {
      network = "10.0.0.0"
      netmask = "255.0.0.0"
    },
    {
      network = "172.16.0.0"
      netmask = "255.240.0.0"
    },
  ]
}
```

## Multiple Google domains

Allow users from more than one Google Workspace domain. The domain from `zone_id` is always
included, so only list the extras. This requires marking the Google OAuth app **External**.

```hcl
module "openvpn" {
  # ...required inputs...

  allowed_domains = [
    "example.com",
    "subsidiary.com",
  ]
}
```

## Tuning scale and instance types

```hcl
module "openvpn" {
  # ...required inputs...

  instance_type                         = "c6in.xlarge"
  asg_min_size                          = 2
  asg_max_size                          = 6
  autoscaling_target_cpu                = 50
  autoscaling_target_network_percentage = 50

  portal_instance_type = "t3a.medium"
  portal_workers_count = 8
}
```

## Replica region for a us-east-1 deployment

When the module is deployed in `us-east-1`, point replication at a different region:

```hcl
module "openvpn" {
  # ...required inputs...

  replication_region = "us-west-2" # must differ from the deploy region
}
```

## Custom backup policy

```hcl
module "openvpn" {
  # ...required inputs...

  enable_efs_backup         = true
  efs_backup_schedule       = "cron(0 5 * * ? *)" # 05:00 UTC daily
  efs_backup_retention_days = 730                 # two years
}
```

## Routing alarms to SNS

```hcl
module "openvpn" {
  # ...required inputs...

  alarm_emails        = ["oncall@example.com"]
  sns_topic_alarm_arn = aws_sns_topic.alerts.arn
}
```
