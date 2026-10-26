variable "name" {
  description = "Name prefix, e.g. tfplatform-dev."
  type        = string
}

variable "environment" {
  description = "Environment name shown on the web page (dev or prod)."
  type        = string
}

variable "app_version" {
  description = "Version label shown on the web page."
  type        = string
  default     = "1.0.0"
}

variable "table_name" {
  description = "DynamoDB table the app writes to."
  type        = string
}

variable "table_arn" {
  description = "ARN of that table (used to scope IAM permissions)."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets the function runs in."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group for the function."
  type        = string
}

variable "memory_size" {
  description = "Memory in MB (128-10240). More memory also means more CPU."
  type        = number
  default     = 128
}

variable "timeout_seconds" {
  description = "Maximum run time per request."
  type        = number
  default     = 10
}

variable "reserved_concurrency" {
  description = "Max concurrent executions (-1 = no limit). Needs an account concurrency limit above 10."
  type        = number
  default     = -1
}

variable "log_level" {
  description = "Python log level: DEBUG, INFO, WARNING or ERROR."
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR"], var.log_level)
    error_message = "log_level must be DEBUG, INFO, WARNING or ERROR."
  }
}

variable "log_retention_days" {
  description = "How long to keep logs."
  type        = number
  default     = 7
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
