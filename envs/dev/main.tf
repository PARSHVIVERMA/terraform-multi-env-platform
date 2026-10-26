###############################################################################
# ENVIRONMENT ROOT MODULE
#
# This file is IDENTICAL in envs/dev and envs/prod.
# The ONLY differences between environments live in:
#   - terraform.tfvars  (sizes, retention, protection flags)
#   - backend.tf        (which state bucket is used)
#
# Prove it in the interview:  diff envs/dev/main.tf envs/prod/main.tf
###############################################################################

locals {
  name = "${var.project}-${var.environment}" # e.g. tfplatform-dev
}

module "network" {
  source = "../../modules/network"

  name               = local.name
  vpc_cidr           = var.vpc_cidr
  azs                = var.azs
  enable_flow_logs   = var.enable_flow_logs
  log_retention_days = var.log_retention_days
}

module "database" {
  source = "../../modules/dynamodb"

  name                   = local.name
  read_capacity          = var.db_read_capacity
  write_capacity         = var.db_write_capacity
  point_in_time_recovery = var.db_point_in_time_recovery
  deletion_protection    = var.db_deletion_protection
}

module "app" {
  source = "../../modules/lambda_app"

  name                 = local.name
  environment          = var.environment
  app_version          = var.app_version
  table_name           = module.database.table_name
  table_arn            = module.database.table_arn
  subnet_ids           = module.network.private_subnet_ids
  security_group_id    = module.network.lambda_security_group_id
  memory_size          = var.lambda_memory_mb
  reserved_concurrency = var.lambda_reserved_concurrency
  log_level            = var.log_level
  log_retention_days   = var.log_retention_days
}

module "monitoring" {
  source = "../../modules/monitoring"

  name                     = local.name
  environment              = var.environment
  function_name            = module.app.function_name
  table_name               = module.database.table_name
  alert_email              = var.alert_email
  max_invocations_per_hour = var.max_invocations_per_hour
}
