variable "alb_access_log_force_destroy" {
  description = "Destroy S3 bucket with access logs even if non-empty"
  type        = bool
  default     = false
}

variable "allowed_domains" {
  description = <<-EOT
    List of Google Workspace domains whose users are allowed to connect to the VPN.

    The OpenVPN portal uses Google OAuth for authentication. Only users with email
    addresses from the specified domains can authenticate and download VPN profiles.

    Important notes:
    - The domain from zone_id is AUTOMATICALLY added to this list
    - For multi-domain support, your Google OAuth app must be "external" type
    - Each domain must be verified in your Google Cloud Console
    - Users must have active Google Workspace accounts

    Example:
    allowed_domains = [
      "company.com",
      "subsidiary.com"
    ]

    If zone_id points to example.com, the effective list will be:
    ["example.com", "company.com", "subsidiary.com"]

    Default: [] (only the zone domain is allowed)
  EOT
  type        = list(string)
  default     = []
}

variable "asg_ami" {
  description = "Image for EC2 instances"
  type        = string
  default     = null
}

variable "asg_health_check_grace_period" {
  description = <<-EOT
    Auto Scaling Group health check grace period in seconds.

    This is the time AWS waits after instance launch before checking health status.
    During this period, instances won't be terminated even if they fail health checks.

    Why 600 seconds (10 minutes)?
    The OpenVPN server bootstrap process includes:
    1. Cloud-init package installation (~2-3 minutes)
    2. Puppet run to configure OpenVPN (~3-4 minutes)
    3. OpenVPN service startup (~30 seconds)
    4. EFS mount and certificate generation (~1-2 minutes)
    5. Network Load Balancer health check stabilization (~1 minute)

    Typical bootstrap time: 7-8 minutes
    Grace period provides 2-3 minute buffer for slower instances or high network latency.

    When to increase this value:
    - Custom packages in var.packages that take long to install
    - Complex Puppet manifests (var.puppet_manifest)
    - Large EFS volumes with many existing certificates
    - Regions with slower package mirror speeds

    When to decrease this value:
    - Using pre-baked AMIs (var.asg_ami) with packages pre-installed
    - Minimal Puppet configuration
    - Fast bootstrap observed in testing

    Default: 600 seconds (10 minutes)
  EOT
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

variable "asg_instance_refresh_max_healthy_percentage" {
  description = <<-EOT
    Maximum percentage of healthy instances during ASG instance refresh rolling updates.

    Controls how many extra instances can be launched during instance refresh:
    - 100 = No extra instances (replace one-by-one)
    - 110 = Allow 10% extra instances (DEFAULT - enables faster updates)
    - 200 = Allow double capacity during refresh

    Higher values enable faster updates but temporarily increase costs.
    Lower values reduce costs but slow down deployments.

    Example with asg_min_size=2, asg_max_size=4:
    - 100%: Replace 1 at a time (max 2 instances total)
    - 110%: Can temporarily have 2.2 instances (rounds up to 3)
    - 200%: Can temporarily have 4 instances during refresh

    Default: 110 (recommended balance of speed and cost)
  EOT
  type        = number
  default     = 110

  validation {
    condition     = var.asg_instance_refresh_max_healthy_percentage >= 100 && var.asg_instance_refresh_max_healthy_percentage <= 200
    error_message = "The asg_instance_refresh_max_healthy_percentage must be between 100 and 200."
  }
}

variable "backend_subnet_ids" {
  description = <<-EOT
    List of private subnet IDs where OpenVPN server instances and Portal ECS tasks will be deployed.

    Requirements:
    - Minimum 2 subnets (AWS high availability best practice)
    - Must be in different availability zones
    - Should have outbound internet access (via NAT Gateway) for package installation
    - Used for both OpenVPN EC2 instances and Portal ECS tasks

    The number of subnets determines default values for:
    - portal_task_min_count (defaults to length of this list)
    - asg_min_size (defaults to length of this list)

    Example: ["subnet-12345678", "subnet-87654321"]

    Required.
  EOT
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
  description = <<-EOT
    EC2 instance type for OpenVPN server instances.

    Recommendation: c6in family (compute-optimized, network-optimized)

    Why compute-optimized for VPN?
    - OpenVPN encryption/decryption is CPU-intensive
    - C-series instances provide better performance per dollar for VPN workloads
    - Higher single-thread performance benefits VPN connection handling

    Recommended instance types:
    - c6in.large (DEFAULT): 2 vCPU, 4 GB RAM, 25 Gbps network - Best balance for production
    - c6in.xlarge: 4 vCPU, 8 GB RAM, 30 Gbps network - High user count (>100 concurrent)
    - c6in.2xlarge: 8 vCPU, 16 GB RAM, 40 Gbps network - Very high throughput needs
    - t3a.small: 2 vCPU, 2 GB RAM, 5 Gbps network - Development/testing only

    Instance type impacts autoscaling:
    - var.autoscaling_target_network_percentage uses the instance's baseline network bandwidth
    - Larger instances = higher network bandwidth threshold for autoscaling
    - Example: c6in.large (25 Gbps) @ 60% = scales at 15 Gbps
    - Example: c6in.xlarge (30 Gbps) @ 60% = scales at 18 Gbps

    Cost comparison (us-east-1, on-demand):
    - c6in.large: ~$82/month (RECOMMENDED)
    - m6in.large: ~$102/month (general-purpose, 19% more expensive)
    - t3a.small: ~$15/month (testing only, limited network performance)

    Network performance:
    - c6in family: 25-200 Gbps (network-optimized)
    - m6in family: 25-200 Gbps (network-optimized)
    - m7i family: Up to 12.5 Gbps (general-purpose)
    - t3/t3a family: Up to 5 Gbps (burstable)

    When to use different instance families:
    - c6in: Best for production VPN (CPU + network optimized)
    - m6in/m7i: If you need more RAM for additional services
    - t3/t3a: Development, testing, or very low user count (<10 users)

    Default: "c6in.large"
  EOT
  type        = string
  default     = "c6in.large"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "The instance_type must be a valid EC2 instance type (e.g., t3.micro, c6in.large, m6in.large)."
  }
}

variable "key_pair_name" {
  description = <<-EOT
    SSH keypair name for accessing OpenVPN server instances.

    ⚠️  SECURITY WARNING:
    - SSH access should be limited to emergency troubleshooting only
    - Use AWS Systems Manager Session Manager for routine access instead
    - Restrict security group to allow SSH only from trusted IP ranges
    - Consider using short-lived SSH certificates instead of long-lived keys
    - Rotate SSH keys regularly
    - Monitor SSH access via CloudWatch and VPC Flow Logs

    The key pair must exist in AWS before applying this module.

    If not specified (null), the module will generate a temporary key pair.
    However, for production use, you should provide a managed key pair.

    Example: "my-openvpn-emergency-key"

    Default: null (module generates a temporary key)
  EOT
  type        = string
  default     = null
}

variable "lb_subnet_ids" {
  description = <<-EOT
    List of public subnet IDs where the Network Load Balancer will be created.

    Requirements:
    - Minimum 2 subnets (AWS NLB requirement - must span at least 2 availability zones)
    - Must be PUBLIC subnets with internet gateway route
    - Must be in different availability zones
    - These subnets host the NLB endpoints that VPN clients connect to

    The NLB will:
    - Accept VPN client connections on TCP port 1194
    - Forward traffic to OpenVPN servers in backend_subnet_ids
    - Have DNS name registered in Route53 zone

    Example: ["subnet-public-1", "subnet-public-2"]

    Required.
  EOT
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
  description = <<-EOT
    Number of Unicorn worker processes in the OpenVPN portal web application.

    The portal runs as a Flask application served by Unicorn. Each worker process
    can handle one request at a time. More workers = more concurrent users.

    Recommended worker count by instance type:
    - t3.nano / t3a.nano (2 vCPU, 0.5 GB RAM): 2 workers
    - t3.small / t3a.small (2 vCPU, 2 GB RAM): 4 workers (DEFAULT)
    - t3.medium (2 vCPU, 4 GB RAM): 4-6 workers
    - t3.large (2 vCPU, 8 GB RAM): 6-8 workers

    Formula: (2 x CPU cores) + 1
    Example: t3.small (2 vCPU) = (2 x 2) + 1 = 5 workers (4 is conservative)

    Memory per worker: ~150-200 MB
    CPU per worker: ~0.5 vCPU under load

    When to increase:
    - High concurrent user count (>20 simultaneous logins)
    - Slow authentication response times
    - Using larger instance types (portal_instance_type)

    When to decrease:
    - Very small instance types (t3.nano)
    - Low user count (<10 total users)
    - Memory pressure in container logs

    Note: More workers = more memory usage. Ensure portal_instance_type
    has sufficient RAM. Monitor ECS task memory utilization in CloudWatch.

    Default: 4 (suitable for t3.small with moderate user load)
  EOT
  type        = number
  default     = 4
}

variable "portal_task_min_count" {
  description = "Minimum number of ECS tasks for the OpenVPN portal service. Defaults to the number of backend subnets for high availability."
  type        = number
  default     = null
}

variable "portal_task_max_count" {
  description = "Maximum number of ECS tasks for the OpenVPN portal service. Defaults to portal_task_min_count + 1."
  type        = number
  default     = null
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
  description = <<-EOT
    List of network routes to push to VPN clients.

    These routes tell VPN clients which traffic should be sent through the VPN tunnel.
    Commonly used to route RFC1918 private networks or specific application networks.

    Format:
    - network: Network address in IPv4 format (e.g., "10.0.0.0")
    - netmask: Network mask in IPv4 format (e.g., "255.0.0.0")

    Example:
    routes = [
      {
        network = "10.0.0.0"
        netmask = "255.0.0.0"
      },
      {
        network = "172.16.0.0"
        netmask = "255.240.0.0"
      }
    ]

    Note: Routes are pushed to clients via OpenVPN configuration.
    Clients will route matching traffic through the VPN tunnel.

    Default: [] (no custom routes - only VPN subnet routed through tunnel)
  EOT
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
  description = <<-EOT
    Service name used for DNS hostname and resource naming.

    This value is used to:
    - Create the Route53 DNS record (e.g., openvpn.example.com)
    - Name EC2 instances and other AWS resources
    - Generate CloudWatch log group names (/aws/openvpn/{environment}/{service_name})
    - Prefix autoscaling policy names

    Default: "openvpn"
  EOT
  type        = string
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
  description = <<-EOT
    Route53 hosted zone ID where the OpenVPN service will be accessible.

    The module will:
    - Create an A record pointing to the Network Load Balancer
    - Use the zone's domain name for DNS resolution (e.g., openvpn.example.com)
    - Automatically add the zone's domain to allowed_domains for Google OAuth

    Example: "Z1234567890ABC"

    Required. Must be a valid Route53 hosted zone ID.
  EOT
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

variable "autoscaling_target_cpu" {
  description = "Target CPU utilization percentage for autoscaling. Applied to both OpenVPN ASG and Portal ECS service."
  type        = number
  default     = 60
  validation {
    condition     = var.autoscaling_target_cpu > 0 && var.autoscaling_target_cpu <= 100
    error_message = "The autoscaling_target_cpu must be between 1 and 100."
  }
}

variable "autoscaling_target_network_percentage" {
  description = "Target network utilization as a percentage of the instance type's baseline bandwidth. Used for OpenVPN ASG network-based autoscaling."
  type        = number
  default     = 60
  validation {
    condition     = var.autoscaling_target_network_percentage > 0 && var.autoscaling_target_network_percentage <= 100
    error_message = "The autoscaling_target_network_percentage must be between 1 and 100."
  }
}

variable "enable_efs_backup" {
  description = "Enable AWS Backup for EFS file system containing OpenVPN configuration and certificates."
  type        = bool
  default     = true
}

variable "efs_backup_schedule" {
  description = "Cron expression for EFS backup schedule. Default: daily at 2 AM UTC (cron(0 2 * * ? *))."
  type        = string
  default     = "cron(0 2 * * ? *)"
}

variable "efs_backup_retention_days" {
  description = "Number of days to retain EFS backups. Default: 365 days (matches log retention for compliance)."
  type        = number
  default     = 365
  validation {
    condition     = var.efs_backup_retention_days >= 1
    error_message = "The efs_backup_retention_days must be at least 1 day."
  }
}
