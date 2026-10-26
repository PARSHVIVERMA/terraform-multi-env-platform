variable "project" {
  description = "Project name prefix (must match the bootstrap project name)."
  type        = string
  default     = "tfplatform"
}

variable "environment" {
  description = "Environment name."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "ap-south-1"
}

variable "owner" {
  description = "Owner tag (your name or GitHub username)."
  type        = string
}

variable "app_version" {
  description = "Version label shown on the web page."
  type        = string
  default     = "1.0.0"
}

# ---------------- network ----------------
variable "vpc_cidr" {
  description = "VPC CIDR. Must be different in each environment so they could be peered later."
  type        = string
}

variable "azs" {
  description = "Availability Zones to use. Listed explicitly so the plan never changes when AWS adds a new zone."
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "enable_flow_logs" {
  description = "Turn on VPC Flow Logs."
  type        = bool
  default     = false
}

# ---------------- database ----------------
variable "db_read_capacity" {
  description = "DynamoDB read capacity units."
  type        = number
  default     = 1
}

variable "db_write_capacity" {
  description = "DynamoDB write capacity units."
  type        = number
  default     = 1
}

variable "db_point_in_time_recovery" {
  description = "Enable continuous backups."
  type        = bool
  default     = false
}

variable "db_deletion_protection" {
  description = "Block deletion of the table. MUST be true in prod."
  type        = bool
  default     = false

  # Guardrail: nobody can turn off deletion protection in prod by accident.
  validation {
    condition     = var.environment != "prod" || var.db_deletion_protection
    error_message = "db_deletion_protection must be true when environment is prod."
  }
}

# ---------------- app ----------------
variable "lambda_memory_mb" {
  description = "Lambda memory in MB."
  type        = number
  default     = 128
}

variable "lambda_reserved_concurrency" {
  description = "Max concurrent executions (-1 = no limit)."
  type        = number
  default     = -1
}

variable "log_level" {
  description = "App log level."
  type        = string
  default     = "INFO"
}

variable "log_retention_days" {
  description = "Days to keep CloudWatch logs."
  type        = number
  default     = 7
}

# ---------------- monitoring ----------------
variable "alert_email" {
  description = "Email for alarm notifications (empty = none)."
  type        = string
  default     = ""
}

variable "max_invocations_per_hour" {
  description = "Cost-guard alarm threshold."
  type        = number
  default     = 1000
}
