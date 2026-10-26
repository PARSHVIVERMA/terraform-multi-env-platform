# ============================================================================
# DEV: small, cheap, easy to destroy and rebuild
# ============================================================================
environment = "dev"
owner       = "PARSHVIVERMA" # <-- change me
app_version = "1.1.0"

# Network
vpc_cidr         = "10.10.0.0/16"
azs              = ["ap-south-1a", "ap-south-1b"]
enable_flow_logs = false

# Database
db_read_capacity          = 1
db_write_capacity         = 1
db_point_in_time_recovery = false
db_deletion_protection    = false

# App
lambda_memory_mb            = 128
lambda_reserved_concurrency = -1
log_level                   = "DEBUG"
log_retention_days          = 3

# Monitoring
alert_email              = "" # optional: your email for dev alerts
max_invocations_per_hour = 500
