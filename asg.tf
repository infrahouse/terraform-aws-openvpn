
module "userdata" {
  source                   = "registry.infrahouse.com/infrahouse/cloud-init/aws"
  version                  = "1.12.4"
  environment              = var.environment
  role                     = "openvpn_server"
  puppet_debug_logging     = var.puppet_debug_logging
  puppet_environmentpath   = var.puppet_environmentpath
  puppet_hiera_config_path = var.puppet_hiera_config_path
  puppet_module_path       = var.puppet_module_path
  puppet_root_directory    = var.puppet_root_directory
  puppet_manifest          = var.puppet_manifest
  pre_runcmd = [
    "aws ec2 modify-instance-attribute --no-source-dest-check --instance-id $(ec2metadata --instance-id)"
  ]
  packages = concat(
    var.packages,
    [
      "awscli",
      "nfs-common"
    ]
  )
  extra_files = var.extra_files
  extra_repos = var.extra_repos

  custom_facts = merge(
    var.puppet_custom_facts,
    {
      openvpn : {
        ca_key_passphrase_secret : module.ca_passkey.secret_name
        openvpn_port : local.openvpn_tcp_port
        routes : var.routes
      }
    },
    {
      "efs" : {
        "file_system_id" : aws_efs_file_system.openvpn-config.id
        "dns_name" : aws_efs_file_system.openvpn-config.dns_name
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
  image_id      = var.asg_ami == null ? data.aws_ami.ubuntu.id : var.asg_ami
  iam_instance_profile {
    arn = module.instance_profile.instance_profile_arn
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
  name                  = local.asg_name
  max_size              = var.asg_max_size == null ? length(var.backend_subnet_ids) + 1 : var.asg_max_size
  min_size              = var.asg_min_size == null ? length(var.backend_subnet_ids) : var.asg_min_size
  vpc_zone_identifier   = var.backend_subnet_ids
  health_check_type     = "ELB"
  max_instance_lifetime = 90 * 24 * 3600
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
    }
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
}
