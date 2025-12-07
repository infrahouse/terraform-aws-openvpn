# CloudWatch Log Group for OpenVPN application logs
resource "aws_cloudwatch_log_group" "openvpn" {
  name              = "/aws/openvpn/${var.environment}/${var.service_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(
    local.default_module_tags,
    {
      Name = "openvpn-${var.environment}-${var.service_name}-logs"
    }
  )
}