data "aws_region" "current" {}
data "aws_default_tags" "provider" {}
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_ami" "ubuntu_pro" {
  most_recent = true

  filter {
    name   = "name"
    values = [local.ami_name_pattern_pro]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name = "state"
    values = [
      "available"
    ]
  }

  owners = [local.canonical_owner_id]
}


data "aws_subnet" "selected" {
  id = var.backend_subnet_ids[0]
}

data "aws_route53_zone" "current" {
  provider = aws.dns
  zone_id  = var.zone_id
}

data "aws_vpc" "selected" {
  id = data.aws_subnet.selected.vpc_id
}

# The AMI is pinned by exact image-id (Canonical's Ubuntu Pro or a user-supplied
# override), so an owners filter would add nothing and cannot be known for overrides.
#trivy:ignore:aws-ami-ensure-ami-has-owners
data "aws_ami" "selected" {
  filter {
    name = "image-id"
    values = [
      var.asg_ami == null ? data.aws_ami.ubuntu_pro.id : var.asg_ami
    ]
  }
}

data "aws_kms_key" "efs_default" {
  key_id = "alias/aws/elasticfilesystem"
}

# Query instance type characteristics for autoscaling network bandwidth calculations
data "aws_ec2_instance_type" "openvpn" {
  instance_type = var.instance_type
}
