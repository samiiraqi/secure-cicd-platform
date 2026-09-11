# bootstrap/github-oidc

Creates the AWS-side identity the GitHub Actions pipeline authenticates
with: an OIDC provider trusting `token.actions.githubusercontent.com`, and
three IAM roles (`plan`, `staging-deploy`, `production-deploy`) the
workflow assumes via short-lived tokens - no AWS access keys are ever
stored in GitHub.

## Why this is separate from environments/*

This is a chicken-and-egg problem: the pipeline needs these roles to exist
*before* it can run `terraform plan`/`apply` on anything else, so they
can't be created by the pipeline itself. Apply this **once, manually**,
with your own (human) AWS credentials, before the GitHub Actions pipeline
runs for the first time. It changes rarely - only when the repo moves, or
you want to adjust what the pipeline is allowed to touch.

## One-time setup

1. Bootstrap the Terraform state backend first, if you haven't:
   ```bash
   ../../scripts/bootstrap-backend.sh
   ```
2. Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in your
   GitHub org/repo and the state bucket name from step 1.
3. Apply with your own AWS credentials (this is the one place in the repo
   you run Terraform locally against a real account):
   ```bash
   terraform init
   terraform apply
   ```
4. Take the three `*_role_arn` outputs and configure them in GitHub:
   - **Repository variable** `AWS_ROLE_ARN` = `plan_role_arn` output (used
     by the lint/security-scan/plan jobs, including on pull requests).
   - **Environment** `staging` (Settings > Environments > New environment)
     → secret `AWS_ROLE_ARN` = `staging_deploy_role_arn` output.
   - **Environment** `production` → secret `AWS_ROLE_ARN` =
     `production_deploy_role_arn` output, **plus a required reviewers
     protection rule** - this is the manual approval gate from the pipeline
     spec. Nothing in the workflow YAML enforces the approval; GitHub's own
     Environment protection rule does, and the production IAM role's trust
     policy only accepts tokens carrying `environment:production`, so the
     two are tied together.
5. Also set the repository variables the workflows read: `AWS_REGION`,
   `TF_STATE_BUCKET`, `TF_LOCK_TABLE` (same values as `backend.tf` /
   `scripts/bootstrap-backend.sh`).

## Design notes

- **Three roles, not one.** `plan` is read-only and assumable from any
  workflow run in this repo (pushes, PRs) - safe to use before human
  review. `staging-deploy` / `production-deploy` can create/modify/destroy
  resources, and each is trusted *only* for the OIDC `sub` claim GitHub
  sets when a job declares `environment: staging` /
  `environment: production` - see the comment in `main.tf`.
- **Least privilege, with a documented limit.** IAM and S3 permissions are
  scoped by resource-name prefix (`${project_name}-*`) - these two
  services are the highest privilege-escalation risk and both support
  resource-level ARNs. EC2/ECS/ELB/CloudWatch/etc. use a wildcard resource
  because most of their write actions don't support resource-level IAM
  conditions at all; tightening that further means an account-level
  permissions boundary or SCP, which is out of scope for a project-level
  Terraform config.
- Not managed via the CI pipeline's own state file - it has its own local
  state in `bootstrap/github-oidc/terraform.tfstate`. For a real
  multi-person team, move this to the same S3 backend under its own key
  (`bootstrap/terraform.tfstate`) once more than one person needs to run
  it.

## Inputs / Outputs

See `variables.tf` and `outputs.tf`.
