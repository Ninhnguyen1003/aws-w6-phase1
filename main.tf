terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment_tag
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  name_prefix = var.project_name
}

# ---------------------------------------------------------------------------
# EC2 – Flask app
# ---------------------------------------------------------------------------

resource "aws_security_group" "flask" {
  name        = "${local.name_prefix}-flask-sg"
  description = "W6 Flask EC2 security group"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP for Flask"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH (Security Guard will revoke if 0.0.0.0/0)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "flask" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.flask.id]
  user_data              = file("${path.module}/user_data/flask_setup.sh")

  tags = {
    Name        = "${local.name_prefix}-flask"
    Environment = var.environment_tag
  }
}

# ---------------------------------------------------------------------------
# Lambda packages
# ---------------------------------------------------------------------------

data "archive_file" "security_guard" {
  type        = "zip"
  source_file = "${path.module}/lambda/security_guard/lambda_function.py"
  output_path = "${path.module}/build/security_guard.zip"
}

data "archive_file" "cost_guard" {
  type        = "zip"
  source_file = "${path.module}/lambda/cost_guard/lambda_function.py"
  output_path = "${path.module}/build/cost_guard.zip"
}

# ---------------------------------------------------------------------------
# IAM – least privilege
# ---------------------------------------------------------------------------

resource "aws_iam_role" "security_guard" {
  name = "${local.name_prefix}-security-guard-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "security_guard" {
  name = "${local.name_prefix}-security-guard-policy"
  role = aws_iam_role.security_guard.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DescribeSecurityGroups"
        Effect = "Allow"
        Action = [
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSecurityGroupRules"
        ]
        Resource = "*"
      },
      {
        Sid    = "RevokeOpenSSH"
        Effect = "Allow"
        Action = [
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DeleteSecurityGroupRule"
        ]
        Resource = "*"
      },
      {
        Sid    = "PublishCustomMetric"
        Effect = "Allow"
        Action = ["cloudwatch:PutMetricData"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "W6/Security"
          }
        }
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.name_prefix}-security-guard:*"
      }
    ]
  })
}

resource "aws_iam_role" "cost_guard" {
  name = "${local.name_prefix}-cost-guard-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "cost_guard" {
  name = "${local.name_prefix}-cost-guard-policy"
  role = aws_iam_role.cost_guard.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DescribeInstances"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "StopDevInstances"
        Effect = "Allow"
        Action = ["ec2:StopInstances"]
        Resource = "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/Environment" = var.environment_tag
          }
        }
      },
      {
        Sid    = "PublishCustomMetric"
        Effect = "Allow"
        Action = ["cloudwatch:PutMetricData"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "W6/Cost"
          }
        }
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.name_prefix}-cost-guard:*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Lambda functions
# ---------------------------------------------------------------------------

resource "aws_lambda_function" "security_guard" {
  function_name    = "${local.name_prefix}-security-guard"
  role             = aws_iam_role.security_guard.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.security_guard.output_path
  source_code_hash = data.archive_file.security_guard.output_base64sha256
  timeout          = 60
  memory_size      = 128

  environment {
    variables = {
      METRIC_NAMESPACE = "W6/Security"
      METRIC_NAME      = "SSHRulesRevoked"
    }
  }
}

resource "aws_cloudwatch_log_group" "security_guard" {
  name              = "/aws/lambda/${aws_lambda_function.security_guard.function_name}"
  retention_in_days = 7
}

resource "aws_lambda_function" "cost_guard" {
  function_name    = "${local.name_prefix}-cost-guard"
  role             = aws_iam_role.cost_guard.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.cost_guard.output_path
  source_code_hash = data.archive_file.cost_guard.output_base64sha256
  timeout          = 60
  memory_size      = 128

  environment {
    variables = {
      ENVIRONMENT_TAG  = var.environment_tag
      METRIC_NAMESPACE = "W6/Cost"
      METRIC_NAME      = "InstancesStopped"
    }
  }
}

resource "aws_cloudwatch_log_group" "cost_guard" {
  name              = "/aws/lambda/${aws_lambda_function.cost_guard.function_name}"
  retention_in_days = 7
}

# ---------------------------------------------------------------------------
# EventBridge schedules
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "security_guard" {
  name                = "${local.name_prefix}-security-guard-schedule"
  description         = "Run Security Guard Lambda on schedule"
  schedule_expression = var.security_guard_schedule
}

resource "aws_cloudwatch_event_target" "security_guard" {
  rule      = aws_cloudwatch_event_rule.security_guard.name
  target_id = "security-guard-lambda"
  arn       = aws_lambda_function.security_guard.arn
}

resource "aws_lambda_permission" "security_guard_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_guard.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.security_guard.arn
}

resource "aws_cloudwatch_event_rule" "cost_guard" {
  name                = "${local.name_prefix}-cost-guard-schedule"
  description         = "Stop dev-tagged EC2 instances on schedule"
  schedule_expression = var.cost_guard_schedule
}

resource "aws_cloudwatch_event_target" "cost_guard" {
  rule      = aws_cloudwatch_event_rule.cost_guard.name
  target_id = "cost-guard-lambda"
  arn       = aws_lambda_function.cost_guard.arn
}

resource "aws_lambda_permission" "cost_guard_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_guard.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cost_guard.arn
}

# ---------------------------------------------------------------------------
# CloudWatch – custom metric alarm (optional SNS)
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "alarms" {
  count = var.alarm_email != "" ? 1 : 0
  name  = "${local.name_prefix}-alarms"
}

resource "aws_sns_topic_subscription" "alarm_email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "ssh_revoked" {
  alarm_name          = "${local.name_prefix}-ssh-revoked"
  alarm_description   = "Alert when Security Guard revokes open SSH rules"
  namespace           = "W6/Security"
  metric_name         = "SSHRulesRevoked"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = var.alarm_email != "" ? [aws_sns_topic.alarms[0].arn] : []
}

resource "aws_cloudwatch_metric_alarm" "ec2_cpu" {
  alarm_name          = "${local.name_prefix}-ec2-cpu-high"
  alarm_description   = "EC2 CPU utilization above 80%"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions = {
    InstanceId = aws_instance.flask.id
  }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = var.alarm_email != "" ? [aws_sns_topic.alarms[0].arn] : []
}

# ---------------------------------------------------------------------------
# CloudWatch Dashboard
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "w6" {
  dashboard_name = "${local.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "EC2 CPU Utilization"
          region = var.aws_region
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.flask.id]
          ]
          period = 300
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Security Guard – SSH Rules Revoked (custom metric)"
          region = var.aws_region
          metrics = [
            ["W6/Security", "SSHRulesRevoked"]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Cost Guard – Instances Stopped (custom metric)"
          region = var.aws_region
          metrics = [
            ["W6/Cost", "InstancesStopped"]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Lambda Invocations"
          region = var.aws_region
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.security_guard.function_name, { stat = "Sum" }],
            ["...", aws_lambda_function.cost_guard.function_name, { stat = "Sum" }]
          ]
          period = 300
        }
      }
    ]
  })
}
