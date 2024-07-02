data "aws_caller_identity" "this" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}
