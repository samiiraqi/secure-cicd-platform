variable "project_name" {
  description = "Project name prefix applied to IAM role/policy names."
  type        = string
  default     = "secure-cicd"
}

variable "aws_region" {
  description = "AWS region for the provider (roles themselves are global)."
  type        = string
  default     = "us-east-1"
}

variable "github_org" {
  description = "GitHub organization or username that owns the repository (e.g. 'my-org' in 'my-org/secure-cicd-platform')."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without the org prefix)."
  type        = string
}

variable "create_oidc_provider" {
  description = "Whether to create the GitHub Actions OIDC provider. AWS allows only ONE OIDC provider per URL per account - if a different project already created https://token.actions.githubusercontent.com in this account, set this to false and pass its ARN via existing_oidc_provider_arn instead."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "ARN of an existing GitHub OIDC provider to reuse. Required when create_oidc_provider = false."
  type        = string
  default     = null
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket used for Terraform remote state (from scripts/bootstrap-backend.sh), so the deploy roles can be scoped to it instead of granted broad S3 access."
  type        = string
}

variable "state_lock_table_name" {
  description = "Name of the DynamoDB table used for Terraform state locking (from scripts/bootstrap-backend.sh)."
  type        = string
  default     = "secure-cicd-tf-locks"
}
