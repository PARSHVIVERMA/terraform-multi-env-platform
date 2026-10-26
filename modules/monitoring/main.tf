###############################################################################
# MODULE: monitoring
#
# Always Free: 10 CloudWatch alarms, 3 dashboards, 1,000 SNS email
# notifications per month. This module uses 3 alarms + 1 dashboard per env,
# so dev + prod = 6 alarms and 2 dashboards (inside the free limits).
###############################################################################

data "aws_region" "current" {}

resource "aws_sns_topic" "alerts" {
  #checkov:skip=CKV_AWS_26:CloudWatch alarms cannot publish to a topic encrypted with the AWS-managed SNS key; a customer-managed key costs ~$1/month.
  name = "${var.name}-alerts"
  tags = var.tags
}

# Email subscription. AWS sends a confirmation email - you must click the link.
resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# 1. Any error in the app
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.name}-lambda-errors"
  alarm_description   = "The ${var.environment} app returned errors."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = var.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.error_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

# 2. DynamoDB is being throttled (traffic is above the free capacity)
resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  alarm_name          = "${var.name}-dynamodb-throttles"
  alarm_description   = "Requests to the ${var.environment} table are being throttled."
  namespace           = "AWS/DynamoDB"
  metric_name         = "WriteThrottleEvents"
  dimensions          = { TableName = var.table_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

# 3. COST GUARD: unusually many requests in one hour (someone spamming the URL)
resource "aws_cloudwatch_metric_alarm" "cost_guard" {
  alarm_name          = "${var.name}-cost-guard-invocations"
  alarm_description   = "More than ${var.max_invocations_per_hour} requests in 1 hour. Check for abuse before the free tier runs out."
  namespace           = "AWS/Lambda"
  metric_name         = "Invocations"
  dimensions          = { FunctionName = var.function_name }
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 1
  threshold           = var.max_invocations_per_hour
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

locals {
  region = data.aws_region.current.region

  lambda_metrics = [
    ["AWS/Lambda", "Invocations", "FunctionName", var.function_name],
    ["AWS/Lambda", "Errors", "FunctionName", var.function_name],
  ]

  dynamodb_metrics = [
    ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", var.table_name],
    ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", var.table_name],
  ]

  alarm_arns = [
    aws_cloudwatch_metric_alarm.lambda_errors.arn,
    aws_cloudwatch_metric_alarm.dynamodb_throttles.arn,
    aws_cloudwatch_metric_alarm.cost_guard.arn,
  ]
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${var.name}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          title   = "Lambda requests and errors (${var.environment})"
          region  = local.region
          stat    = "Sum"
          period  = 300
          view    = "timeSeries"
          metrics = local.lambda_metrics
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          title   = "Lambda duration in ms (${var.environment})"
          region  = local.region
          stat    = "Average"
          period  = 300
          view    = "timeSeries"
          metrics = [["AWS/Lambda", "Duration", "FunctionName", var.function_name]]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          title   = "DynamoDB capacity used (${var.environment})"
          region  = local.region
          stat    = "Sum"
          period  = 300
          view    = "timeSeries"
          metrics = local.dynamodb_metrics
        }
      },
      {
        type   = "alarm"
        x      = 12
        y      = 6
        width  = 12
        height = 6

        properties = {
          title  = "Alarms (${var.environment})"
          alarms = local.alarm_arns
        }
      },
    ]
  })
}
