# ============================================================================
# PROD: same code as dev, stricter settings
# ============================================================================
environment = "prod"
owner       = "PARSHVIVERMA" # <-- change me
app_version = "1.1.0"

# Network (different CIDR from dev so they never overlap)
vpc_cidr         = "10.20.0.0/16"
azs              = ["ap-south-1a", "ap-south-1b"]
enable_flow_logs = true # audit rejected traffic (near-zero volume, inside free 5 GB)

# Database
db_read_capacity          = 2
db_write_capacity         = 2
db_point_in_time_recovery = true # restore to any second in the last 35 days
db_deletion_protection    = true # validation in variables.tf forces this in prod

# App
lambda_memory_mb            = 256
lambda_reserved_concurrency = -1
log_level                   = "INFO"
log_retention_days          = 30

# Monitoring
alert_email              = "vparshvi@gmail.com" # <-- put your email here to receive prod alerts
max_invocations_per_hour = 1000
