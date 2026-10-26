variable "name" {
  description = "Name prefix for all resources, e.g. tfplatform-dev."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC. Use a different range per environment."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block, e.g. 10.10.0.0/16."
  }
}

variable "azs" {
  description = "Availability Zones to create private subnets in (at least 2)."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "Use at least 2 Availability Zones for high availability."
  }
}

variable "enable_flow_logs" {
  description = "Turn on VPC Flow Logs (rejected traffic only)."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "How long to keep flow logs."
  type        = number
  default     = 7
}

variable "tags" {
  description = "Extra tags for every resource in this module."
  type        = map(string)
  default     = {}
}
