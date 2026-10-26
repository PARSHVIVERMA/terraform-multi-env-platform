###############################################################################
# MODULE: dynamodb
#
# PROVISIONED capacity (not on-demand) on purpose:
#   AWS "Always Free" covers 25 read + 25 write capacity units and 25 GB,
#   for every account, forever. On-demand mode is billed per request instead.
#   Provisioned mode also puts a hard ceiling on cost: traffic above the
#   capacity is throttled, never billed.
#
# Keep the TOTAL across all tables in the account at or below 25 RCU / 25 WCU.
###############################################################################

resource "aws_dynamodb_table" "this" {
  #checkov:skip=CKV_AWS_119:AWS-owned key encryption is free; a customer-managed KMS key costs ~$1/month.
  #checkov:skip=CKV_AWS_28:PITR is a per-environment variable: ON in prod, OFF in dev to keep dev disposable.
  #checkov:skip=CKV2_AWS_16:Auto scaling is deliberately off so capacity (and cost) can never grow past the free tier.
  name         = "${var.name}-visits"
  billing_mode = "PROVISIONED"

  read_capacity  = var.read_capacity
  write_capacity = var.write_capacity

  hash_key = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  # Encrypted at rest with the AWS-owned key (free, always on).
  server_side_encryption {
    enabled = false # false = AWS-owned key; true would switch to a paid KMS key
  }

  # Continuous backups: restore to any second in the last 35 days.
  point_in_time_recovery {
    enabled = var.point_in_time_recovery
  }

  # In prod this blocks "terraform destroy" and console deletes.
  deletion_protection_enabled = var.deletion_protection

  tags = merge(var.tags, { Name = "${var.name}-visits" })
}
