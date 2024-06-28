data "aws_iam_policy_document" "required_permissions" {
  statement {
    actions = ["sts:GetCallerIdentity"]
    resources = [
      "*"
    ]
  }
}

resource "aws_iam_policy" "required" {
  policy = data.aws_iam_policy_document.required_permissions.json
}

resource "random_string" "profile-suffix" {
  length  = 12
  special = false
}

module "instance_profile" {
  source       = "registry.infrahouse.com/infrahouse/instance-profile/aws"
  version      = "1.4.0"
  permissions  = data.aws_iam_policy_document.instance_permissions.json
  profile_name = "openvpn-${random_string.profile-suffix.result}"
  extra_policies = merge(
    {
      required : aws_iam_policy.required.arn
    },
    var.extra_policies
  )
}

