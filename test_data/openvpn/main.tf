resource "aws_key_pair" "mediapc" {
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDpgAP1z1Lxg9Uv4tam6WdJBcAftZR4ik7RsSr6aNXqfnTj4civrhd/q8qMqF6wL//3OujVDZfhJcffTzPS2XYhUxh/rRVOB3xcqwETppdykD0XZpkHkc8XtmHpiqk6E9iBI4mDwYcDqEg3/vrDAGYYsnFwWmdDinxzMH1Gei+NPTmTqU+wJ1JZvkw3WBEMZKlUVJC/+nuv+jbMmCtm7sIM4rlp2wyzLWYoidRNMK97sG8+v+mDQol/qXK3Fuetj+1f+vSx2obSzpTxL4RYg1kS6W1fBlSvstDV5bQG4HvywzN5Y8eCpwzHLZ1tYtTycZEApFdy+MSfws5vPOpggQlWfZ4vA8ujfWAF75J+WABV4DlSJ3Ng6rLMW78hVatANUnb9s4clOS8H6yAjv+bU3OElKBkQ10wNneoFIMOA3grjPvPp5r8dI0WDXPIznJThDJO5yMCy3OfCXlu38VDQa1sjVj1zAPG+Vn2DsdVrl50hWSYSB17Zww0MYEr8N5rfFE= aleks@MediaPC"
}

module "openvpn" {
  source = "../../"
  providers = {
    aws     = aws
    aws.dns = aws
  }
  backend_subnet_ids           = var.backend_subnet_ids
  lb_subnet_ids                = var.lb_subnet_ids
  zone_id                      = data.aws_route53_zone.test-zone.zone_id
  key_pair_name                = aws_key_pair.mediapc.key_name
  asg_min_size                 = 1
  asg_max_size                 = 1
  portal-image                 = "303467602807.dkr.ecr.us-east-2.amazonaws.com/portal:latest"
  google_oauth_client_writer   = "arn:aws:iam::303467602807:role/aws-reserved/sso.amazonaws.com/us-west-1/AWSReservedSSO_AWSAdministratorAccess_422821c726d81c14"
  alb_access_log_force_destroy = true
}
