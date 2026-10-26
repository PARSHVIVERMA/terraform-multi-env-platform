###############################################################################
# MODULE: lambda_app
#
# A Python Lambda function, running inside the private VPC, exposed through a
# Lambda Function URL (free HTTPS endpoint - no load balancer, no API Gateway).
#
# Always Free: 1,000,000 requests + 400,000 GB-seconds per month.
# arm64 (Graviton) is used because it is ~20% cheaper per GB-second once you
# leave the free tier.
###############################################################################

# Zip the source code. The hash is used so Lambda only updates when code changes.
data "archive_file" "code" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/build/${var.name}.zip"
}

# -----------------------------------------------------------------------------
# IAM: least-privilege execution role
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "lambda" {
  #checkov:skip=CKV_AWS_111:The EC2 network-interface and X-Ray APIs do not support resource-level permissions, so "*" is required by AWS.
  #checkov:skip=CKV_AWS_356:Same reason as above; every other statement is scoped to a single ARN.
  # Only the two DynamoDB actions the code uses, only on this env's table.
  statement {
    sid       = "UseOwnTableOnly"
    actions   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
    resources = [var.table_arn]
  }

  # Write logs only to this function's log group.
  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }

  # Needed to attach the function to the VPC (create/remove network interfaces).
  # These EC2 APIs do not support resource-level restrictions, so "*" is required.
  statement {
    sid = "VpcNetworkInterfaces"

    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeSubnets",
      "ec2:DeleteNetworkInterface",
      "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses",
    ]
    resources = ["*"]
  }

  # X-Ray tracing (Always Free: 100,000 traces per month).
  statement {
    sid       = "XRayTracing"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "least-privilege"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

# -----------------------------------------------------------------------------
# Logs: created by Terraform so we control retention (Lambda's default is
# "never expire", which slowly costs money).
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda" {
  #checkov:skip=CKV_AWS_158:CloudWatch default encryption is used; a customer-managed KMS key costs ~$1/month.
  #checkov:skip=CKV_AWS_338:Short retention keeps log storage inside the free 5 GB.
  name              = "/aws/lambda/${var.name}-app"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# -----------------------------------------------------------------------------
# The function
# -----------------------------------------------------------------------------
resource "aws_lambda_function" "app" {
  #checkov:skip=CKV_AWS_116:A dead-letter queue is not useful for synchronous HTTP requests.
  #checkov:skip=CKV_AWS_173:Env vars hold no secrets and are encrypted with the free AWS-managed key.
  #checkov:skip=CKV_AWS_272:Code signing needs AWS Signer; out of scope for this project.
  #checkov:skip=CKV_AWS_115:New AWS accounts have a concurrency limit of 10, which blocks reserved concurrency. Configurable via var.reserved_concurrency.
  function_name = "${var.name}-app"
  description   = "Visit counter for ${var.environment}"
  role          = aws_iam_role.lambda.arn

  filename         = data.archive_file.code.output_path
  source_code_hash = data.archive_file.code.output_base64sha256

  runtime       = "python3.12"
  handler       = "app.handler"
  architectures = ["arm64"]
  memory_size   = var.memory_size
  timeout       = var.timeout_seconds

  reserved_concurrent_executions = var.reserved_concurrency

  environment {
    variables = {
      TABLE_NAME  = var.table_name
      ENVIRONMENT = var.environment
      APP_VERSION = var.app_version
      LOG_LEVEL   = var.log_level
    }
  }

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.security_group_id]
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.lambda.name
  }

  tracing_config {
    mode = "Active"
  }

  tags = merge(var.tags, { Name = "${var.name}-app" })

  depends_on = [aws_iam_role_policy.lambda]
}

# -----------------------------------------------------------------------------
# Function URL: free public HTTPS endpoint
# -----------------------------------------------------------------------------
resource "aws_lambda_function_url" "app" {
  #checkov:skip=CKV_AWS_258:Public demo web page. Switch to AWS_IAM (or put CloudFront in front) for private apps.
  function_name      = aws_lambda_function.app.function_name
  authorization_type = "NONE" # public demo page; see README for the AWS_IAM option

  cors {
    allow_origins = ["*"]
    allow_methods = ["GET"]
    max_age       = 300
  }
}

# Public function URLs need BOTH permissions below (AWS requirement since late 2025).
resource "aws_lambda_permission" "public_url" {
  #checkov:skip=CKV_AWS_301:Intentionally public demo page served through a Function URL.
  statement_id           = "AllowPublicFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.app.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "public_invoke" {
  #checkov:skip=CKV_AWS_301:Intentionally public demo page served through a Function URL.
  statement_id  = "AllowPublicInvokeViaUrl"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app.function_name
  principal     = "*"
}
