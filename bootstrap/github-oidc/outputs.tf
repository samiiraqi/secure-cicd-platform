output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider (created here, or the existing one passed in)."
  value       = local.oidc_provider_arn
}

output "plan_role_arn" {
  description = "IAM role ARN for read-only `terraform plan` runs (PRs and pushes, no GitHub Environment). Set as the AWS_ROLE_ARN repository variable/secret used by the lint/security-scan/plan jobs."
  value       = aws_iam_role.plan.arn
}

output "staging_deploy_role_arn" {
  description = "IAM role ARN for `terraform apply` in staging. Set as a secret named AWS_ROLE_ARN on the GitHub 'staging' Environment."
  value       = aws_iam_role.staging_deploy.arn
}

output "production_deploy_role_arn" {
  description = "IAM role ARN for `terraform apply` in production. Set as a secret named AWS_ROLE_ARN on the GitHub 'production' Environment. Only assumable by a workflow job that declares `environment: production` - pair this with a required-reviewers protection rule on that GitHub Environment for the manual approval gate."
  value       = aws_iam_role.production_deploy.arn
}
