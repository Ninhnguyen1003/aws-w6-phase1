variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Prefix for resource names"
  type        = string
  default     = "w6-personal"
}

variable "key_name" {
  description = "Existing EC2 key pair name"
  type        = string
  default     = "ninh_dev"
}

variable "instance_type" {
  description = "EC2 instance type (t3.micro for free tier / lowest cost)"
  type        = string
  default     = "t3.micro"
}

variable "environment_tag" {
  description = "Environment tag value used by Cost Guard"
  type        = string
  default     = "dev"
}

variable "security_guard_schedule" {
  description = "EventBridge schedule for Security Guard Lambda"
  type        = string
  default     = "rate(15 minutes)"
}

variable "cost_guard_schedule" {
  description = "EventBridge schedule for Cost Guard Lambda (stop dev instances)"
  type        = string
  default     = "cron(0 14 * * ? *)" # 21:00 ICT daily
}

variable "allowed_ssh_cidr" {
  description = "Safe SSH CIDR (not 0.0.0.0/0); Security Guard revokes open SSH"
  type        = string
  default     = "0.0.0.0/0" # intentionally open for demo; Security Guard will revoke
}

variable "alarm_email" {
  description = "Optional email for CloudWatch alarm SNS (leave empty to skip SNS)"
  type        = string
  default     = ""
}
