output "ec2_instance_id" {
  description = "Flask EC2 instance ID"
  value       = aws_instance.flask.id
}

output "ec2_public_ip" {
  description = "Flask EC2 public IP"
  value       = aws_instance.flask.public_ip
}

output "flask_url" {
  description = "URL to access the Flask app"
  value       = "http://${aws_instance.flask.public_ip}"
}

output "security_group_id" {
  description = "Flask security group ID (Security Guard monitors this)"
  value       = aws_security_group.flask.id
}

output "security_guard_lambda_arn" {
  description = "Security Guard Lambda ARN"
  value       = aws_lambda_function.security_guard.arn
}

output "cost_guard_lambda_arn" {
  description = "Cost Guard Lambda ARN"
  value       = aws_lambda_function.cost_guard.arn
}

output "cloudwatch_dashboard_name" {
  description = "CloudWatch dashboard name"
  value       = aws_cloudwatch_dashboard.w6.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "CloudWatch dashboard console URL"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.w6.dashboard_name}"
}

output "ssh_revoked_alarm_name" {
  description = "Custom metric alarm for revoked SSH rules"
  value       = aws_cloudwatch_metric_alarm.ssh_revoked.alarm_name
}

output "manual_test_commands" {
  description = "Quick commands for W6 evidence collection"
  value = {
    invoke_security_guard = "aws lambda invoke --function-name ${aws_lambda_function.security_guard.function_name} --region ${var.aws_region} out.json && type out.json"
    invoke_cost_guard     = "aws lambda invoke --function-name ${aws_lambda_function.cost_guard.function_name} --region ${var.aws_region} out.json && type out.json"
    open_ssh_for_demo       = "aws ec2 authorize-security-group-ingress --group-id ${aws_security_group.flask.id} --protocol tcp --port 22 --cidr 0.0.0.0/0 --region ${var.aws_region}"
  }
}
