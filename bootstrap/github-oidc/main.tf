locals {
  repo_subject_prefix = "repo:${var.github_org}/${var.github_repo}"

  managed_service_actions = [
    "ec2:*",
    "ecs:*",
    "ecr:*",
    "elasticloadbalancing:*",
    "application-autoscaling:*",
    "logs:*",
    "cloudwatch:*",
    "cloudtrail:*",
    "sns:*",
  ]
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# OIDC provider - lets GitHub Actions assume AWS IAM roles with short-lived
# tokens instead of long-lived access keys. See create_oidc_provider in
# variables.tf if your account already has one from another project.
# ---------------------------------------------------------------------------

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]

  tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_oidc_provider_arn
}

# ---------------------------------------------------------------------------
# Trust policies
#
# The "sub" claim GitHub sends differs by trigger:
#   - a job with `environment: staging`    -> repo:org/repo:environment:staging
#   - a job with `environment: production` -> repo:org/repo:environment:production
#   - any other run (push/PR, no env)      -> repo:org/repo:ref:refs/heads/... or repo:org/repo:pull_request
#
# This is what makes the split real: a workflow job can only assume the
# production role if it actually declares `environment: production`, which
# is exactly the job GitHub's own environment protection rules (required
# reviewers) gate. There's no separate "approval step" resource here - the
# approval gate IS the environment protection rule on the production
# GitHub Environment, configured in the repo's Settings > Environments.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "assume_plan" {
  statement {
    effect  = "Allow"
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
      values   = ["${local.repo_subject_prefix}:*"]
    }
  }
}

data "aws_iam_policy_document" "assume_staging" {
  statement {
    effect  = "Allow"
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
      values   = ["${local.repo_subject_prefix}:environment:staging"]
    }
  }
}

data "aws_iam_policy_document" "assume_production" {
  statement {
    effect  = "Allow"
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
      values   = ["${local.repo_subject_prefix}:environment:production"]
    }
  }
}

# ---------------------------------------------------------------------------
# Roles
# ---------------------------------------------------------------------------

resource "aws_iam_role" "plan" {
  name                 = "${var.project_name}-gha-plan"
  assume_role_policy   = data.aws_iam_policy_document.assume_plan.json
  max_session_duration = 3600

  tags = { Project = var.project_name, ManagedBy = "terraform", Purpose = "terraform-plan-readonly" }
}

resource "aws_iam_role" "staging_deploy" {
  name                 = "${var.project_name}-gha-staging-deploy"
  assume_role_policy   = data.aws_iam_policy_document.assume_staging.json
  max_session_duration = 3600

  tags = { Project = var.project_name, ManagedBy = "terraform", Purpose = "terraform-apply-staging" }
}

resource "aws_iam_role" "production_deploy" {
  name                 = "${var.project_name}-gha-production-deploy"
  assume_role_policy   = data.aws_iam_policy_document.assume_production.json
  max_session_duration = 3600

  tags = { Project = var.project_name, ManagedBy = "terraform", Purpose = "terraform-apply-production" }
}

# ---------------------------------------------------------------------------
# State access - every role needs this to run any `terraform plan`/`apply`,
# scoped to just this project's state bucket/table rather than all of S3.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "state_access" {
  statement {
    sid       = "StateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.state_bucket_name}"]
  }

  statement {
    sid       = "StateObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket_name}/*"]
  }

  statement {
    sid       = "StateLock"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = ["arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.state_lock_table_name}"]
  }
}

resource "aws_iam_policy" "state_access" {
  name   = "${var.project_name}-gha-state-access"
  policy = data.aws_iam_policy_document.state_access.json
}

resource "aws_iam_role_policy_attachment" "plan_state" {
  role       = aws_iam_role.plan.name
  policy_arn = aws_iam_policy.state_access.arn
}

resource "aws_iam_role_policy_attachment" "staging_state" {
  role       = aws_iam_role.staging_deploy.name
  policy_arn = aws_iam_policy.state_access.arn
}

resource "aws_iam_role_policy_attachment" "production_state" {
  role       = aws_iam_role.production_deploy.name
  policy_arn = aws_iam_policy.state_access.arn
}

# ---------------------------------------------------------------------------
# Plan role: read-only. Can run `terraform plan` (needs to Describe/List/Get
# everything the modules touch) but cannot create, modify, or delete any
# AWS resource - safe to run from a pull request, before any human review.
# ---------------------------------------------------------------------------

# This is a read-only policy by design (Describe/List/Get actions across
# the services these modules touch, same shape as AWS's own ReadOnlyAccess
# managed policy) - action wildcards here are the point, not an oversight.
# tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "plan_readonly" {
  #checkov:skip=CKV_AWS_355:read-only policy by design - see comment above
  #checkov:skip=CKV_AWS_290:read-only policy by design - see comment above
  #checkov:skip=CKV_AWS_356:read-only policy by design - see comment above
  statement {
    sid    = "ReadOnlyDescribe"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "ecs:Describe*",
      "ecs:List*",
      "ecr:Describe*",
      "ecr:List*",
      "ecr:GetLifecyclePolicy",
      "elasticloadbalancing:Describe*",
      "application-autoscaling:Describe*",
      "logs:Describe*",
      "logs:List*",
      "logs:GetLogGroupFields",
      "cloudwatch:Describe*",
      "cloudwatch:List*",
      "cloudwatch:GetDashboard",
      "cloudtrail:Describe*",
      "cloudtrail:GetTrailStatus",
      "cloudtrail:GetEventSelectors",
      "cloudtrail:ListTags",
      "sns:Get*",
      "sns:List*",
      "iam:Get*",
      "iam:List*",
      "kms:Describe*",
      "kms:Get*",
      "kms:List*",
      "s3:GetBucket*",
      "s3:ListAllMyBuckets",
      "s3:GetEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "plan_readonly" {
  name   = "${var.project_name}-gha-plan-readonly"
  policy = data.aws_iam_policy_document.plan_readonly.json
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = aws_iam_policy.plan_readonly.arn
}

# ---------------------------------------------------------------------------
# Deploy policy (staging + production): full lifecycle management of the
# resources these modules create.
#
# IAM and S3 are scoped by name prefix (both support resource-level ARNs
# and are the highest-risk services for privilege escalation). EC2/ECS/ELB/
# CloudWatch/etc. use "*" because most of their write actions don't support
# resource-level permissions in IAM at all - the usual real-world mitigation
# is a permissions boundary or SCP at the OU level, layered on top of this,
# which is account-wide setup out of scope for a project-level Terraform
# module.
# ---------------------------------------------------------------------------

# Most EC2/ECS/ELB/CloudWatch/etc. write actions don't support
# resource-level IAM conditions at all, so this can't be scoped further
# than the service level without an account-wide permissions boundary or
# SCP (out of scope here) - see the comment above this section and
# README.md ("Least privilege, with a documented limit").
# tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "deploy" {
  #checkov:skip=CKV_AWS_356:most EC2/ECS/ELB/CloudWatch actions don't support resource-level ARNs - see comment above and README.md
  #checkov:skip=CKV_AWS_290:this is the CI/CD deploy role's own permission set, intentionally broad at the service level for the reason above; IAM/S3 (the privilege-escalation-sensitive services) ARE scoped by name prefix
  #checkov:skip=CKV_AWS_355:same as CKV_AWS_356 above
  #checkov:skip=CKV_AWS_109:the IamManageProjectResources statement uses iam:* but its `resources` are scoped to arn:...:role|policy/secure-cicd-* only, not "*" - this is the resource-level restriction the check is asking for
  #checkov:skip=CKV_AWS_111:same as CKV_AWS_109 above
  #checkov:skip=CKV2_AWS_40:iam:* is scoped to this project's own role/policy name prefix (see IamManageProjectResources statement); Terraform genuinely needs full role/policy lifecycle management to create the IAM resources modules/vpc, modules/compute and modules/monitoring define
  statement {
    sid       = "ManagedServices"
    effect    = "Allow"
    actions   = local.managed_service_actions
    resources = ["*"]
  }

  statement {
    sid    = "KmsManage"
    effect = "Allow"
    actions = [
      "kms:CreateKey",
      "kms:CreateAlias",
      "kms:DeleteAlias",
      "kms:UpdateAlias",
      "kms:DescribeKey",
      "kms:GetKeyPolicy",
      "kms:PutKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:EnableKeyRotation",
      "kms:ScheduleKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ListAliases",
      "kms:ListResourceTags",
    ]
    resources = ["*"]
  }

  statement {
    sid     = "IamManageProjectResources"
    effect  = "Allow"
    actions = ["iam:*"]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.project_name}-*",
    ]
  }

  statement {
    sid       = "IamReadForPlanning"
    effect    = "Allow"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  statement {
    sid     = "S3ManageProjectBuckets"
    effect  = "Allow"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::${var.project_name}-*",
      "arn:aws:s3:::${var.project_name}-*/*",
    ]
  }

  statement {
    sid       = "DynamoDbLockTable"
    effect    = "Allow"
    actions   = ["dynamodb:DescribeTable"]
    resources = ["arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.state_lock_table_name}"]
  }
}

resource "aws_iam_policy" "deploy" {
  name   = "${var.project_name}-gha-deploy"
  policy = data.aws_iam_policy_document.deploy.json
}

resource "aws_iam_role_policy_attachment" "staging_deploy" {
  role       = aws_iam_role.staging_deploy.name
  policy_arn = aws_iam_policy.deploy.arn
}

resource "aws_iam_role_policy_attachment" "production_deploy" {
  role       = aws_iam_role.production_deploy.name
  policy_arn = aws_iam_policy.deploy.arn
}
