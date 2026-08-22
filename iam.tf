data "aws_iam_policy_document" "instance_permissions" {
  source_policy_documents = var.extra_instance_profile_permissions != null ? [var.extra_instance_profile_permissions] : []

  statement {
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
  # These EC2 describe actions require a wildcard resource ("*") because
  # they are read-only list operations that do not support resource-level permissions.
  # - ec2:DescribeInstances: Used by infrahouse-toolkit (ASGInstance class) to read instance tags and state
  # - ec2:DescribeTags: Used by CloudWatch agent's ec2tagger to add instance tags to metrics
  # AWS API limitation - see: https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonec2.html
  statement {
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
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
  # profile::boot_security_upgrade removes this tag once security updates are
  # applied, so Inspector's first scan sees a patched host. Scoped three ways:
  # only this tag key, only instances, and only instances in this ASG.
  # local.asg_name rather than aws_autoscaling_group.openvpn.name on purpose:
  # the resource reference would order this grant after the ASG has already
  # started launching tagged instances.
  statement {
    actions = [
      "ec2:DeleteTags",
    ]
    resources = [
      "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:instance/*"
    ]
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["InspectorEc2Exclusion"]
    }
    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/aws:autoscaling:groupName"
      values   = [local.asg_name]
    }
  }
  statement {
    actions = [
      "autoscaling:SetInstanceHealth",
    ]
    resources = [
      "arn:aws:autoscaling:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/${local.asg_name}"
    ]
  }
  # CloudWatch Logs permissions for shipping OpenVPN application logs
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = [
      "${aws_cloudwatch_log_group.openvpn.arn}:*"
    ]
  }
  # CloudWatch Metrics permissions for publishing custom metrics
  # PutMetricData doesn't support resource-level permissions, but we can limit by namespace
  statement {
    actions = [
      "cloudwatch:PutMetricData"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = [var.cloudwatch_namespace]
    }
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
