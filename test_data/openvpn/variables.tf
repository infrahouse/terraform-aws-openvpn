variable "environment" {
  default = "development"
}
variable "region" {}
variable "role_arn" {}
variable "test_zone" {}

variable "backend_subnet_ids" {}
variable "lb_subnet_ids" {}
variable "vpc_id" {}