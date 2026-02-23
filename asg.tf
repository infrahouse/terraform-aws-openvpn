
module "userdata" {
  source                   = "registry.infrahouse.com/infrahouse/cloud-init/aws"
  version                  = "2.2.3"
  environment              = var.environment
  role                     = "openvpn_server"
  puppet_debug_logging     = var.puppet_debug_logging
  puppet_environmentpath   = var.puppet_environmentpath
  puppet_hiera_config_path = var.puppet_hiera_config_path
  puppet_module_path       = var.puppet_module_path
  puppet_root_directory    = var.puppet_root_directory
  puppet_manifest          = var.puppet_manifest
  ubuntu_codename          = var.ubuntu_codename
  pre_runcmd = [
    "aws ec2 modify-instance-attribute --no-source-dest-check --instance-id $(ec2metadata --instance-id)"
  ]
  packages = concat(
    var.packages,
    [
      "awscli",
      "nfs-common",
    ]
  )
  gzip_userdata = var.gzip_userdata
  extra_files   = var.extra_files
  extra_repos   = var.extra_repos

  custom_facts = merge(
    var.puppet_custom_facts,
    {
      openvpn : {
        ca_key_passphrase_secret : module.ca_passkey.secret_name
        openvpn_port : local.openvpn_tcp_port
        routes : var.routes
        cloudwatch_log_group : aws_cloudwatch_log_group.openvpn.name
        cloudwatch_namespace : var.cloudwatch_namespace
      }
    },
    {
      "efs" : {
        "file_system_id" : aws_efs_file_system.openvpn-config-enc.id
        "dns_name" : aws_efs_file_system.openvpn-config-enc.dns_name
      }
    },
    var.smtp_credentials_secret != null ? {
      postfix : {
        smtp_credentials : var.smtp_credentials_secret
      }
    } : {}
  )
}

resource "aws_launch_template" "openvpn" {
  name_prefix   = "openvpn-"
  instance_type = var.instance_type
  key_name      = local.key_pair_name
  image_id      = var.asg_ami == null ? data.aws_ami.ubuntu_pro.id : var.asg_ami
  iam_instance_profile {
    arn = module.instance_profile.instance_profile_arn
  }
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }
  block_device_mappings {
    device_name = data.aws_ami.selected.root_device_name
    ebs {
      volume_size           = var.root_volume_size
      delete_on_termination = true
    }
  }
  user_data = module.userdata.userdata
  tags      = local.default_module_tags
  vpc_security_group_ids = [
    aws_security_group.openvpn.id
  ]
  tag_specifications {
    resource_type = "volume"
    tags = merge(
      data.aws_default_tags.provider.tags,
      local.default_module_tags
    )
  }
  tag_specifications {
    resource_type = "network-interface"
    tags = merge(
      data.aws_default_tags.provider.tags,
      local.default_module_tags
    )
  }

}

resource "random_string" "asg_name" {
  length  = 6
  special = false
}
locals {
  asg_name = "${aws_launch_template.openvpn.name}-${random_string.asg_name.result}"
}

resource "aws_autoscaling_group" "openvpn" {
  name                      = local.asg_name
  max_size                  = var.asg_max_size == null ? length(var.backend_subnet_ids) + 1 : var.asg_max_size
  min_size                  = var.asg_min_size == null ? length(var.backend_subnet_ids) : var.asg_min_size
  vpc_zone_identifier       = var.backend_subnet_ids
  health_check_type         = "ELB"
  health_check_grace_period = var.asg_health_check_grace_period
  max_instance_lifetime     = 90 * 24 * 3600
  dynamic "launch_template" {
    for_each = var.on_demand_base_capacity == null ? [1] : []
    content {
      id      = aws_launch_template.openvpn.id
      version = aws_launch_template.openvpn.latest_version
    }
  }
  dynamic "mixed_instances_policy" {
    for_each = var.on_demand_base_capacity == null ? [] : [1]
    content {
      instances_distribution {
        on_demand_base_capacity                  = var.on_demand_base_capacity
        on_demand_percentage_above_base_capacity = 0
      }
      launch_template {
        launch_template_specification {
          launch_template_id = aws_launch_template.openvpn.id
          version            = aws_launch_template.openvpn.latest_version
        }
      }
    }
  }
  target_group_arns = [
    aws_lb_target_group.openvpn.arn
  ]
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100
      max_healthy_percentage = var.asg_instance_refresh_max_healthy_percentage
      instance_warmup        = var.asg_health_check_grace_period
      skip_matching          = false
    }
    triggers = ["tag"]
  }
  tag {
    key                 = "Name"
    propagate_at_launch = true
    value               = "openvpn"
  }
  dynamic "tag" {
    for_each = merge(
      local.default_module_tags,
      data.aws_default_tags.provider.tags
    )

    content {
      key                 = tag.key
      propagate_at_launch = true
      value               = tag.value
    }
  }
  depends_on = [
    aws_efs_mount_target.openvpn-config-enc
  ]
}

# CPU-based autoscaling policy for OpenVPN ASG
resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "${var.service_name}-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.openvpn.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.autoscaling_target_cpu
  }
}

# Network-based autoscaling policy for OpenVPN ASG
# Uses instance type's baseline network bandwidth to calculate target
# Tracks both NetworkIn and NetworkOut, scales when either direction hits the threshold
resource "aws_autoscaling_policy" "network_target_tracking" {
  name                   = "${var.service_name}-network-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.openvpn.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    customized_metric_specification {
      # NetworkIn metric - used for calculation only, not returned
      metrics {
        id = "m1"
        metric_stat {
          metric {
            namespace   = "AWS/EC2"
            metric_name = "NetworkIn"
            dimensions {
              name  = "AutoScalingGroupName"
              value = aws_autoscaling_group.openvpn.name
            }
          }
          stat = "Average"
        }
        return_data = false
      }
      # NetworkOut metric - used for calculation only, not returned
      metrics {
        id = "m2"
        metric_stat {
          metric {
            namespace   = "AWS/EC2"
            metric_name = "NetworkOut"
            dimensions {
              name  = "AutoScalingGroupName"
              value = aws_autoscaling_group.openvpn.name
            }
          }
          stat = "Average"
        }
        return_data = false
      }
      # Return the maximum of NetworkIn and NetworkOut
      # This ensures we scale when EITHER direction is saturated
      metrics {
        id          = "e1"
        expression  = "MAX([m1,m2])"
        return_data = true
      }
    }
    target_value = local.autoscaling_target_network
  }
}
