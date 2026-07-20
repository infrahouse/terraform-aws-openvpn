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

variable "google_project" {
  description = "GCP project the WIF resources are created in."
  type        = string
}

variable "google_workspace_admin_email" {
  description = "Workspace admin the VPN impersonates to read the directory (domain-wide-delegation subject)."
  type        = string
}
