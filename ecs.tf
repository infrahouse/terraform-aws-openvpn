module "openvpn-portal" {
  source  = "registry.infrahouse.com/infrahouse/ecs/aws"
  version = "2.10.0"
  providers = {
    aws     = aws
    aws.dns = aws.dns
  }
  service_name                              = "openvpn-portal"
  docker_image                              = var.portal-image
  load_balancer_subnets                     = var.lb_subnet_ids
  asg_subnets                               = var.backend_subnet_ids
  zone_id                                   = data.aws_route53_zone.current.zone_id
  dns_names                                 = ["openvpn-portal"]
  internet_gateway_id                       = data.aws_internet_gateway.current.id
  ssh_key_name                              = local.key_pair_name
  container_port                            = 8080
  container_healthcheck_command             = "curl -sf http://localhost:8080/status || exit 1"
  service_health_check_grace_period_seconds = 300
  alb_healthcheck_path                      = "/status"
  alb_healthcheck_response_code_matcher     = "200"
  alb_idle_timeout                          = 600
  task_desired_count                        = 1
  task_min_count                            = 1
  task_max_count                            = 1
  asg_min_size                              = 1
  asg_instance_type                         = "t3.small" # 2vCPU, 2GB RAM
  container_cpu                             = 400        # One vCPU is 1024
  container_memory                          = 400        # Value in MB
  environment                               = var.environment

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
    ]
  )
  task_role_arn = aws_iam_role.openvpn_portal_role.arn
}