variable "region" {}

variable "role_arn" {
  default = null
}

variable "test_zone" {}

variable "backend_subnet_ids" {}

variable "lb_subnet_ids" {}

# --- Google WIF (feature under test) ---------------------------------------
variable "google_project" {
  description = "GCP project that hosts the Workload Identity Federation resources."
  type        = string
}

variable "google_directory_admin_subject" {
  description = "Workspace admin the directory-reader SA impersonates (domain-wide delegation subject)."
  type        = string
}

