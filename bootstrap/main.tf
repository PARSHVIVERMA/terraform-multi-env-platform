###############################################################################
# BOOTSTRAP LAYER
#
# Runs ONCE, from your laptop, with your admin credentials.
# Creates everything the pipelines need before they can run:
#   1. One S3 state bucket PER ENVIRONMENT (dev and prod are fully separated)
#   2. The GitHub OIDC identity provider (so GitHub Actions needs NO AWS keys)
#   3. Two IAM roles PER ENVIRONMENT:
#        gha-<project>-<env>-plan   -> read-only, used on pull requests
#        gha-<project>-<env>-apply  -> can change infra, used only after merge
#
# Cost: S3 state files are a few KB each, so storage and requests round to $0.
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  envs       = toset(var.environments)
  repo       = "${var.github_owner}/${var.github_repo}"

  state_bucket_name = { for env in local.envs : env => "${var.project}-tfstate-${env}-${local.account_id}" }

  oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

# -----------------------------------------------------------------------------
# 1. STATE BUCKETS (one per environment)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "state" {
  #checkov:skip=CKV_AWS_144:Cross-region replication doubles cost; versioning covers recovery for this project.
  #checkov:skip=CKV_AWS_18:Access logging would create a second bucket and extra cost; CloudTrail covers API auditing.
  #checkov:skip=CKV2_AWS_62:Event notifications are not needed for a state bucket.
  #checkov:skip=CKV_AWS_145:SSE-S3 is free; a customer-managed KMS key costs ~$1/month. Upgrade path documented in README.
  for_each = local.envs

  bucket = local.state_bucket_name[each.key]

  # Safety: Terraform refuses to delete a bucket that still has state in it.
  force_destroy = false

  tags = {
    Name        = local.state_bucket_name[each.key]
    Environment = each.key
  }
}

# Versioning = every state change is kept, so a broken state can be rolled back.
resource "aws_s3_bucket_versioning" "state" {
  for_each = local.envs
  bucket   = aws_s3_bucket.state[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption at rest. SSE-S3 (AES256) is free.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  for_each = local.envs
  bucket   = aws_s3_bucket.state[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Nobody on the internet can ever read the state.
resource "aws_s3_bucket_public_access_block" "state" {
  for_each = local.envs
  bucket   = aws_s3_bucket.state[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Disable ACLs completely; access is controlled only by IAM.
resource "aws_s3_bucket_ownership_controls" "state" {
  for_each = local.envs
  bucket   = aws_s3_bucket.state[each.key].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Keep old state versions for 90 days, then delete them (keeps storage near zero).
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  for_each = local.envs
  bucket   = aws_s3_bucket.state[each.key].id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

# Reject any request that is not HTTPS.
data "aws_iam_policy_document" "state_bucket" {
  for_each = local.envs

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.state[each.key].arn,
      "${aws_s3_bucket.state[each.key].arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  for_each = local.envs
  bucket   = aws_s3_bucket.state[each.key].id
  policy   = data.aws_iam_policy_document.state_bucket[each.key].json

  depends_on = [aws_s3_bucket_public_access_block.state]
}

# -----------------------------------------------------------------------------
# 2. GITHUB OIDC PROVIDER (lets GitHub Actions log in to AWS without keys)
# -----------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # AWS no longer checks these for GitHub, but the field is kept for older provider versions.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

# -----------------------------------------------------------------------------
# 3a. PLAN ROLE (one per env) - read-only, used on Pull Requests and drift checks
# -----------------------------------------------------------------------------
# Trust: only THIS repo, only from a pull request or from the main branch.
# Forked repos never receive an OIDC token, so outsiders cannot assume it.
data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"

      values = [
        "repo:${local.repo}:pull_request",
        "repo:${local.repo}:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "plan" {
  for_each = local.envs

  # NOTE: the name starts with "gha-" on purpose. The apply role may only manage
  # IAM roles that start with "<project>-<env>-", so it can never edit itself.
  name                 = "gha-${var.project}-${each.key}-plan"
  description          = "GitHub Actions read-only role for terraform plan in ${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600

  tags = { Environment = each.key }
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  for_each   = local.envs
  role       = aws_iam_role.plan[each.key].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

# The plan role can read state, and may only create/delete the small .tflock file
# that S3-native locking uses. It can NEVER overwrite the state itself.
data "aws_iam_policy_document" "plan_state" {
  for_each = local.envs

  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state[each.key].arn]
  }

  statement {
    sid       = "ReadState"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.state[each.key].arn}/*"]
  }

  statement {
    sid       = "ManageLockFileOnly"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state[each.key].arn}/*.tflock"]
  }
}

resource "aws_iam_role_policy" "plan_state" {
  for_each = local.envs
  name     = "terraform-state-read"
  role     = aws_iam_role.plan[each.key].id
  policy   = data.aws_iam_policy_document.plan_state[each.key].json
}

# -----------------------------------------------------------------------------
# 3b. APPLY ROLE (one per env) - can change infra, ONLY from a GitHub Environment
# -----------------------------------------------------------------------------
# Trust: only jobs that run inside the GitHub Environment with the same name.
# The "prod" GitHub Environment requires a human approval, so nobody can apply
# to prod without that approval - not even the pipeline.
data "aws_iam_policy_document" "apply_trust" {
  for_each = local.envs

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.repo}:environment:${each.key}"]
    }
  }
}

resource "aws_iam_role" "apply" {
  for_each = local.envs

  name                 = "gha-${var.project}-${each.key}-apply"
  description          = "GitHub Actions role for terraform apply in ${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust[each.key].json
  max_session_duration = 3600

  tags = { Environment = each.key }
}

# PowerUserAccess = everything except IAM / Organizations.
resource "aws_iam_role_policy_attachment" "apply_poweruser" {
  for_each   = local.envs
  role       = aws_iam_role.apply[each.key].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "apply_extra" {
  for_each = local.envs

  # IAM is allowed ONLY for roles/policies whose name starts with "<project>-<env>-".
  # So the dev pipeline can create "tfplatform-dev-lambda-role" but can never
  # touch admin roles, the prod roles, or its own gha-* role.
  statement {
    sid = "ScopedIamForThisEnvOnly"

    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy", "iam:TagRole", "iam:UntagRole", "iam:PassRole",
      "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
      "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:role/${var.project}-${each.key}-*",
    ]
  }

  statement {
    sid       = "ServiceLinkedRolesFirstTimeOnly"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/*"]
  }

  # Explicit DENY on every OTHER environment's state bucket.
  # PowerUserAccess allows s3:* everywhere, so this deny is what stops the dev
  # pipeline from reading or corrupting prod state.
  dynamic "statement" {
    for_each = length(setsubtract(local.envs, [each.key])) > 0 ? [1] : []
    content {
      sid     = "DenyOtherEnvironmentState"
      effect  = "Deny"
      actions = ["s3:*"]

      resources = flatten([
        for other in setsubtract(local.envs, [each.key]) : [
          aws_s3_bucket.state[other].arn,
          "${aws_s3_bucket.state[other].arn}/*",
        ]
      ])
    }
  }

  # Defence in depth: deny changes to resources tagged with ANOTHER environment.
  # (True isolation = separate AWS accounts; this is the single-account guardrail.)
  statement {
    sid    = "DenyTouchingOtherEnvironmentResources"
    effect = "Deny"

    actions = [
      "lambda:*", "dynamodb:*", "ec2:*", "logs:*", "cloudwatch:*", "sns:*",
    ]
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [each.key]
    }

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/Environment"
      values   = ["false"]
    }
  }
}

resource "aws_iam_role_policy" "apply_extra" {
  for_each = local.envs
  name     = "scoped-iam-and-env-isolation"
  role     = aws_iam_role.apply[each.key].id
  policy   = data.aws_iam_policy_document.apply_extra[each.key].json
}
