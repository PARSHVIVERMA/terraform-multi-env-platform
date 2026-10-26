# PROD state lives in its OWN bucket. The dev pipeline role is explicitly
# denied access to it, and every prod apply needs a human approval.
#
# Replace 010526263348 with your 12-digit AWS account ID
# (printed by the bootstrap step as "aws_account_id").
terraform {
  backend "s3" {
    bucket       = "tfplatform-tfstate-prod-010526263348"
    key          = "envs/prod/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true # S3-native locking (no DynamoDB lock table needed)
  }
}
