variable "name" {
  description = "Name prefix, e.g. tfplatform-dev."
  type        = string
}

variable "read_capacity" {
  description = "Provisioned read capacity units. Free tier: 25 total across the account."
  type        = number
  default     = 1

  validation {
    condition     = var.read_capacity >= 1 && var.read_capacity <= 10
    error_message = "Keep read_capacity between 1 and 10 to stay inside the free tier."
  }
}

variable "write_capacity" {
  description = "Provisioned write capacity units. Free tier: 25 total across the account."
  type        = number
  default     = 1

  validation {
    condition     = var.write_capacity >= 1 && var.write_capacity <= 10
    error_message = "Keep write_capacity between 1 and 10 to stay inside the free tier."
  }
}

variable "point_in_time_recovery" {
  description = "Enable point-in-time recovery (continuous backups). Costs fractions of a cent for tiny tables."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Block deletion of the table."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
