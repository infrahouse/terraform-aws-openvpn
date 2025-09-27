data "aws_iam_policy_document" "instance_permissions" {
  source_policy_documents = var.extra_instance_profile_permissions != null ? [var.extra_instance_profile_permissions] : []

  statement {
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
  statement {
    actions = [
      "ec2:DescribeInstances",
    ]
    resources = [
      "*"
    ]
  }
  statement {
    actions = [
      "ec2:ModifyInstanceAttribute",
    ]
    resources = [
      "*"
    ]
    condition {
      test = "StringEquals"
      values = [
        aws_autoscaling_group.openvpn.name
      ]
      variable = "ec2:ResourceTag/aws:autoscaling:groupName"
    }
  }
  statement {
    actions = [
      "autoscaling:SetInstanceHealth",
    ]
    resources = [
      "arn:aws:autoscaling:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/${local.asg_name}"
    ]
  }
}

resource "random_string" "profile-suffix" {
  length  = 12
  special = false
}

module "instance_profile" {
  source       = "registry.infrahouse.com/infrahouse/instance-profile/aws"
  version      = "1.9.0"
  permissions  = data.aws_iam_policy_document.instance_permissions.json
  profile_name = "openvpn-${random_string.profile-suffix.result}"
  extra_policies = merge(
    var.extra_policies
  )
}
