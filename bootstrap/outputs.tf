output "aws_account_id" {
  description = "Your AWS account ID. Save this as the GitHub repository variable AWS_ACCOUNT_ID."
  value       = local.account_id
}

output "state_buckets" {
  description = "State bucket per environment. Paste each name into envs/<env>/backend.tf."
  value       = { for env, b in aws_s3_bucket.state : env => b.bucket }
}

output "plan_role_arns" {
  description = "Read-only roles used by pull requests and drift detection."
  value       = { for env, r in aws_iam_role.plan : env => r.arn }
}

output "apply_role_arns" {
  description = "Roles used to apply changes (only from the matching GitHub Environment)."
  value       = { for env, r in aws_iam_role.apply : env => r.arn }
}

output "next_steps" {
  description = "What to do after the bootstrap apply."

  value = <<-EOT

    1. GitHub repo -> Settings -> Secrets and variables -> Actions -> Variables tab:
         AWS_ACCOUNT_ID = ${local.account_id}
         AWS_REGION     = ${var.aws_region}
    2. Replace REPLACE_ACCOUNT_ID with ${local.account_id} in envs/dev/backend.tf and envs/prod/backend.tf
    3. Create GitHub Environments "dev" and "prod" (prod with a required reviewer).
  EOT
}
