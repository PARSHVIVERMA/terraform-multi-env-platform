output "app_url" {
  description = "Open this URL in your browser."
  value       = module.app.function_url
}

output "function_name" {
  description = "Lambda function name."
  value       = module.app.function_name
}

output "table_name" {
  description = "DynamoDB table name."
  value       = module.database.table_name
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.network.vpc_id
}

output "dashboard_name" {
  description = "CloudWatch dashboard name."
  value       = module.monitoring.dashboard_name
}
