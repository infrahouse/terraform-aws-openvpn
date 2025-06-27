data "aws_caller_identity" "this" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_route53_zone" "test-zone" {
  name = var.test_zone
}

data "aws_subnet" "selected" {
  id = var.backend_subnet_ids[0]
}

data "aws_vpc" "mgmt" {
  id = data.aws_subnet.selected.vpc_id
}

data "aws_iam_roles" "sso-admin" {
  name_regex  = "AWSReservedSSO_AWSAdministratorAccess_.*"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}
