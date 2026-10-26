variable "name" {
  description = "Name prefix, e.g. tfplatform-dev."
  type        = string
}

variable "environment" {
  description = "Environment name (dev or prod)."
  type        = string
}

variable "function_name" {
  description = "Lambda function to monitor."
  type        = string
}

variable "table_name" {
  description = "DynamoDB table to monitor."
  type        = string
}

variable "alert_email" {
  description = "Email that receives alarm notifications. Empty string = no email."
  type        = string
  default     = ""
}

variable "error_threshold" {
  description = "Number of errors in 5 minutes that triggers the alarm."
  type        = number
  default     = 1
}

variable "max_invocations_per_hour" {
  description = "Cost guard: alert when requests in one hour go above this."
  type        = number
  default     = 1000
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
