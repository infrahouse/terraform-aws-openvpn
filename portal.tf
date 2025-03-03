module "openvpn-portal" {
  source  = "registry.infrahouse.com/infrahouse/ecs/aws"
  version = "5.3.0"
  providers = {
    aws     = aws
    aws.dns = aws.dns
  }
  environment                               = var.environment
  service_name                              = "${var.service_name}-portal"
  docker_image                              = var.portal-image
  load_balancer_subnets                     = var.lb_subnet_ids
  asg_subnets                               = var.backend_subnet_ids
  zone_id                                   = data.aws_route53_zone.current.zone_id
  dns_names                                 = ["${var.service_name}-portal"]
  internet_gateway_id                       = data.aws_internet_gateway.current.id
  ssh_key_name                              = local.key_pair_name
  container_port                            = 8080
  container_healthcheck_command             = "curl -sf http://localhost:8080/status || exit 1"
  service_health_check_grace_period_seconds = 300
  healthcheck_path                          = "/status"
  healthcheck_response_code_matcher         = "200"
  idle_timeout                              = 600
  task_desired_count                        = 1
  task_min_count                            = 1
  task_max_count                            = 1
  asg_min_size                              = 1
  asg_max_size                              = 1
  on_demand_base_capacity                   = var.on_demand_base_capacity
  asg_instance_type                         = var.portal_instance_type
  container_cpu                             = 400 # One vCPU is 1024
  container_memory                          = 200 # Value in MB
  access_log_force_destroy                  = var.alb_access_log_force_destroy
  task_efs_volumes = {
    data : {
      file_system_id : aws_efs_file_system.openvpn-config.id
      container_path : "/etc/openvpn"
    }
  }

  task_environment_variables = concat(
    [
      {
        name : "DEBUG",
        value : true,
      },
      {
        name : "AWS_DEFAULT_REGION",
        value : data.aws_region.current.name
      },
      {
        name : "FLASK_SECRET_KEY",
        value : module.flask_secret_key.secret_name
      },
      {
        name : "GOOGLE_OAUTH_CLIENT_SECRET_NAME",
        value : module.google_client.secret_name
      },
      {
        name : "OPENVPN_HOSTNAME",
        value : aws_route53_record.vpn_cname.fqdn
      },
      {
        name : "OPENVPN_PORT",
        value : local.openvpn_tcp_port
      },
      {
        name : "WORKERS",
        value : var.portal_workers_count
      }
    ]
  )
  task_role_arn = aws_iam_role.openvpn_portal_role.arn
}
