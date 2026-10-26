output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets."
  value       = aws_subnet.private[*].id
}

output "lambda_security_group_id" {
  description = "Security group to attach to the Lambda function."
  value       = aws_security_group.lambda.id
}

output "dynamodb_endpoint_id" {
  description = "ID of the DynamoDB gateway endpoint."
  value       = aws_vpc_endpoint.dynamodb.id
}
