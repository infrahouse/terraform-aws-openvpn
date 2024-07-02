data "aws_iam_policy_document" "openvpn_portal_role_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    condition {
      test = "StringEquals"
      values = [
        data.aws_caller_identity.current.account_id
      ]
      variable = "aws:SourceAccount"
    }
    condition {
      test = "ArnLike"
      values = [
        "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      ]
      variable = "aws:SourceArn"
    }
  }
}

data "aws_iam_policy_document" "openvpn_portal_role_permissions" {
  statement {
    actions = [
      "sts:GetCallerIdentity"
    ]
    resources = ["*"]
  }
  statement {
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = [
      module.google_client.secret_arn,
    ]
  }
}

resource "aws_iam_policy" "openvpn_portal_role" {
  name_prefix = "openvpn-portal-"
  policy      = data.aws_iam_policy_document.openvpn_portal_role_permissions.json
}

resource "aws_iam_role" "openvpn_portal_role" {
  name_prefix        = "openvpn-portal-"
  assume_role_policy = data.aws_iam_policy_document.openvpn_portal_role_assume.json
}

resource "aws_iam_role_policy_attachment" "task_role" {
  policy_arn = aws_iam_policy.openvpn_portal_role.arn
  role       = aws_iam_role.openvpn_portal_role.name
}
