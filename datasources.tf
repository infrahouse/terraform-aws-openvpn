data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-${var.ubuntu_codename}-*"]
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

  owners = ["099720109477"] # Canonical
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

data "aws_internet_gateway" "current" {
  filter {
    name   = "attachment.vpc-id"
    values = [data.aws_vpc.selected.id]
  }
}

data "aws_ami" "selected" {
  filter {
    name = "image-id"
    values = [
      var.asg_ami == null ? data.aws_ami.ubuntu.id : var.asg_ami
    ]
  }
}
