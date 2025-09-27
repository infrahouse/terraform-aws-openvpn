variable "environment" {
  default = "development"
}
variable "region" {}
variable "role_arn" {
  default = null
}
variable "test_zone" {}

variable "backend_subnet_ids" {}
variable "lb_subnet_ids" {}
