variable "project" {
  description = "Short project name. Used as a prefix for every resource name."
  type        = string
  default     = "tfplatform"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,15}$", var.project))
    error_message = "Use 3-16 lowercase letters, numbers or dashes."
  }
}

variable "aws_region" {
  description = "AWS region for the state buckets."
  type        = string
  default     = "ap-south-1"
}

variable "owner" {
  description = "Your name or GitHub username, added as a tag on every resource."
  type        = string
}

variable "environments" {
  description = "Environments that get their own isolated state bucket and IAM roles."
  type        = list(string)
  default     = ["dev", "prod"]
}

variable "github_owner" {
  description = "Your GitHub username or organisation (the part before the slash in the repo URL)."
  type        = string
}

variable "github_repo" {
  description = "Your GitHub repository name (the part after the slash in the repo URL)."
  type        = string
}

variable "create_github_oidc_provider" {
  description = "Set to false if this AWS account already has the GitHub OIDC provider (only one is allowed per account)."
  type        = bool
  default     = true
}
