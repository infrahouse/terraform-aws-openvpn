variable "alb_access_log_force_destroy" {
  description = "Destroy S3 bucket with access logs even if non-empty"
  type        = bool
  default     = false
}

variable "allowed_domains" {
  description = "List of domains, authenticated users of which will be allowed to connect to VPN. The domain passed via var.zone_id will be added to the list"
  type        = list(string)
  default     = []
}

variable "asg_ami" {
  description = "Image for EC2 instances"
  type        = string
  default     = null
}

variable "asg_health_check_grace_period" {
  description = "ASG will wait up to this number of minutes for instance to become healthy"
  type        = number
  default     = 600
}

variable "asg_min_size" {
  description = "Minimum number of instances in ASG"
  type        = number
  default     = null
}

variable "asg_max_size" {
  description = "Maximum number of instances in ASG"
  type        = number
  default     = null
}

variable "backend_subnet_ids" {
  description = "List of subnet ids where the webserver and database instances will be created"
  type        = list(string)
  validation {
    condition     = length(var.backend_subnet_ids) >= 2
    error_message = "At least two backend subnet IDs must be provided for high availability."
  }
  validation {
    condition     = alltrue([for s in var.backend_subnet_ids : can(regex("^subnet-[a-z0-9]+$", s))])
    error_message = "All backend_subnet_ids must be valid AWS subnet IDs (format: subnet- followed by alphanumeric characters)."
  }
}

variable "environment" {
  description = "Name of environment."
  type        = string
  default     = "development"
  validation {
    condition     = can(regex("^[a-z0-9_]+$", var.environment))
    error_message = "The environment name must contain only lowercase letters, numbers, and underscores (Puppet environment naming requirement)."
  }
}

variable "extra_files" {
  description = "Additional files to create on an instance."
  type = list(
    object(
      {
        content     = string
        path        = string
        permissions = string
      }
    )
  )
  default = []
}

variable "extra_policies" {
  description = "A map of additional policy ARNs to attach to the jumphost role"
  type        = map(string)
  default     = {}
}


variable "extra_repos" {
  description = "Additional APT repositories to configure on an instance."
  type = map(
    object(
      {
        source   = string
        key      = string
        machine  = optional(string)
        authFrom = optional(string)
        priority = optional(number)
      }
    )
  )
  default = {}
}

# Example of the secret content
# {
#  "web": {
#    "client_id": "***.apps.googleusercontent.com",
#    "project_id": "bookstack-424221",
#    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
#    "token_uri": "https://oauth2.googleapis.com/token",
#    "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
#    "client_secret": "***",
#    "redirect_uris": [
#      "https://bookstack.ci-cd.infrahouse.com"
#    ],
#    "javascript_origins": [
#      "https://bookstack.ci-cd.infrahouse.com"
#    ]
#  }
#}
variable "google_oauth_client_writer" {
  description = "ARN of an IAM role that can update content of google_oauth_client secret"
  type        = string
}

variable "instance_type" {
  description = "Instance type to run the OpenVPN instances"
  type        = string
  default     = "m6in.large"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "The instance_type must be a valid EC2 instance type (e.g., t3.micro, m6in.large, c5.xlarge)."
  }
}

variable "key_pair_name" {
  description = "SSH keypair name to be deployed in EC2 instances"
  type        = string
  default     = null
}

variable "lb_subnet_ids" {
  description = "List of subnet ids where the load balancer will be created"
  type        = list(string)
  validation {
    condition     = length(var.lb_subnet_ids) >= 2
    error_message = "At least two load balancer subnet IDs must be provided (AWS requires subnets in at least two availability zones)."
  }
  validation {
    condition     = alltrue([for s in var.lb_subnet_ids : can(regex("^subnet-[a-z0-9]+$", s))])
    error_message = "All lb_subnet_ids must be valid AWS subnet IDs (format: subnet- followed by alphanumeric characters)."
  }
}

variable "on_demand_base_capacity" {
  description = "If specified, the ASG will request spot instances and this will be the minimal number of on-demand instances."
  type        = number
  default     = null
}

variable "portal-image" {
  description = "OpenVPN portal docker image"
  default     = "public.ecr.aws/infrahouse/openvpn-portal:latest"
}

variable "packages" {
  description = "List of packages to install when the instances bootstraps."
  type        = list(string)
  default     = []
}

variable "portal_instance_type" {
  description = "AWS instance type for the portal service"
  type        = string
  default     = "t3.small"
}

variable "portal_workers_count" {
  description = "Number of unicorn workers in OpenVPN portal"
  type        = number
  default     = 4
}

variable "puppet_custom_facts" {
  description = "A map of custom puppet facts"
  type        = any
  default     = {}
}

variable "puppet_debug_logging" {
  description = "Enable debug logging if true."
  type        = bool
  default     = false
}

variable "puppet_environmentpath" {
  description = "A path for directory environments."
  default     = "{root_directory}/environments"
}

variable "puppet_hiera_config_path" {
  description = "Path to hiera configuration file."
  default     = "{root_directory}/environments/{environment}/hiera.yaml"
}

variable "puppet_manifest" {
  description = "Path to puppet manifest. By default ih-puppet will apply {root_directory}/environments/{environment}/manifests/site.pp."
  type        = string
  default     = null
}

variable "puppet_module_path" {
  description = "Path to common puppet modules."
  default     = "{root_directory}/environments/{environment}/modules:{root_directory}/modules"
}

variable "puppet_root_directory" {
  description = "Path where the puppet code is hosted."
  default     = "/opt/puppet-code"
}

variable "root_volume_size" {
  description = "Root volume size in EC2 instance in Gigabytes"
  type        = number
  default     = 30
  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 16384
    error_message = "The root_volume_size must be between 8 GB and 16384 GB (AWS EBS volume size limits)."
  }
}

variable "routes" {
  description = "List of network/netmasks in format 10.x.x.x/255.x.x.x that need to be pushed to a client. [{network: \"10.0.0.0\", netmask: \"255.0.0.0\"}]"
  type = list(
    object(
      {
        network : string,
        netmask : string
      }
    )
  )
  default = []
  validation {
    condition = alltrue(
      [
        for route in var.routes : can(
          regex(
            "^([0-9]{1,3}\\.){3}[0-9]{1,3}$",
            route.network
          )
          ) && can(
          regex(
            "^([0-9]{1,3}\\.){3}[0-9]{1,3}$",
            route.netmask
          )
        )
      ]
    )
    error_message = "All routes must have valid IPv4 format for both network and netmask (e.g., network: \"10.0.0.0\", netmask: \"255.0.0.0\")."
  }
}

variable "service_name" {
  description = "DNS hostname for the service. It's also used to name some resources like EC2 instances."
  default     = "openvpn"
}

variable "smtp_credentials_secret" {
  description = "AWS secret name with SMTP credentials. The secret must contain a JSON with user and password keys."
  type        = string
  default     = null
}

variable "ubuntu_codename" {
  description = "Ubuntu version to use for the OpenVPN server EC2 instance"
  type        = string
  default     = "noble"
}

variable "users" {
  description = "A list of maps with user definitions according to the cloud-init format"
  default     = null
  type        = any
  # Check https://cloudinit.readthedocs.io/en/latest/reference/examples.html#including-users-and-groups
  # for fields description and examples.
  #   type = list(
  #     object(
  #       {
  #         name : string
  #         expiredate : optional(string)
  #         gecos : optional(string)
  #         homedir : optional(string)
  #         primary_group : optional(string)
  #         groups : optional(string) # Comma separated list of strings e.g. groups: users, admin
  #         selinux_user : optional(string)
  #         lock_passwd : optional(bool)
  #         inactive : optional(number)
  #         passwd : optional(string)
  #         no_create_home : optional(bool)
  #         no_user_group : optional(bool)
  #         no_log_init : optional(bool)
  #         ssh_import_id : optional(list(string))
  #         ssh_authorized_keys : optional(list(string))
  #         sudo : any # Can be either false or a list of strings e.g. sudo = ["ALL=(ALL) NOPASSWD:ALL"]
  #         system : optional(bool)
  #         snapuser : optional(string)
  #       }
  #     )
  #   )
}

variable "zone_id" {
  description = "Domain name zone ID where the website will be available"
  type        = string
  validation {
    condition     = can(regex("^Z[A-Z0-9]+$", var.zone_id))
    error_message = "The zone_id must be a valid Route53 hosted zone ID (format: Z followed by alphanumeric characters)."
  }
}

variable "sns_topic_alarm_arn" {
  description = "ARN of SNS topic for Cloudwatch alarms on base EC2 instance."
  type        = string
  default     = null
}

variable "alarm_emails" {
  description = "List of email addresses to receive CloudWatch alarm notifications for the OpenVPN portal ECS service."
  type        = list(string)
}

variable "extra_instance_profile_permissions" {
  description = "A JSON with a permissions policy document. The policy will be attached to the ASG instance profile."
  type        = string
  default     = null
}

variable "cloudinit_extra_commands" {
  description = "Extra commands for run on ASG."
  type        = list(string)
  default     = []
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch Logs for all services (NLB access logs, ECS logs, etc.)"
  type        = number
  default     = 365
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653, 0
    ], var.cloudwatch_log_retention_days)
    error_message = "The cloudwatch_log_retention_days must be a valid CloudWatch Logs retention period (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653, or 0 for never expire)."
  }
}
