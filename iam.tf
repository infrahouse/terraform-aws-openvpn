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
