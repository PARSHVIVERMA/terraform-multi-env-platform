terraform {
  # 1.10+ is required for S3-native state locking (use_lockfile = true)
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # STEP 2 (optional, after the first apply): uncomment this block and run
  #   terraform init -migrate-state
  # to move the bootstrap state from your laptop into S3.
  # backend "s3" {
  #   bucket       = "tfplatform-tfstate-prod-<YOUR_ACCOUNT_ID>"
  #   key          = "bootstrap/terraform.tfstate"
  #   region       = "ap-south-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "Terraform"
      Layer     = "bootstrap"
      Owner     = var.owner
    }
  }
}
