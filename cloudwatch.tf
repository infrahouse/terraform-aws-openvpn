resource "aws_cloudwatch_metric_alarm" "cpu_utilization_alarm" {
  count               = var.sns_topic_alarm_arn != null ? 1 : 0
  alarm_name          = format("CPU Alarm on ASG %s", aws_autoscaling_group.openvpn.name)
  comparison_operator = "GreaterThanThreshold"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  evaluation_periods  = 1
  period              = 60
  threshold           = 90
  namespace           = "AWS/EC2"
  alarm_actions       = [var.sns_topic_alarm_arn]
  alarm_description   = format("%s alarm - CPU exceeds 90 percent", aws_autoscaling_group.openvpn.name)
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.openvpn.name
  }
}
