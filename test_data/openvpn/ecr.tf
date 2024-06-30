resource "aws_ecr_repository" "portal" {
  name         = "portal"
  force_delete = true
}
