output "function_name" {
  description = "Name of the Lambda function."
  value       = aws_lambda_function.app.function_name
}

output "function_url" {
  description = "Public HTTPS URL of the app."
  value       = aws_lambda_function_url.app.function_url
}

output "log_group_name" {
  description = "CloudWatch log group of the function."
  value       = aws_cloudwatch_log_group.lambda.name
}
