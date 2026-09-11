# modules/monitoring

Observability and security-event alerting: a CloudWatch dashboard for
application health, CloudTrail for account-wide API audit logging, and
CIS-Foundations-style alarms wired to SNS.

## What it creates

- **SNS topic** (`alerts`) — encrypted with the AWS-managed SNS key;
  optional email subscription via `alert_email`. Every alarm in this
  module publishes here.
- **CloudWatch Dashboard** — ECS CPU/Memory/running-task-count, ALB
  request count / 5xx / response time / healthy-unhealthy host counts.
- **Application health alarms** — ECS high CPU, ALB elevated 5xx rate,
  ALB unhealthy hosts.
- **CloudTrail** *(only if `enable_cloudtrail = true`)* — multi-region
  trail, log file validation, KMS-encrypted S3 bucket (versioned, public
  access blocked) + KMS-encrypted CloudWatch Logs group.
- **CIS-style security alarms** *(only if `enable_cloudtrail = true`)* —
  metric filters + alarms on CloudTrail events for: unauthorized API
  calls, root account usage, IAM policy changes, Security Group changes,
  NACL changes, CloudTrail config changes, console sign-in failures.

## Design notes: why `enable_cloudtrail` is a toggle

CloudTrail (as configured here — multi-region, account-wide) is an
**account-level** control, not a per-environment one. Creating it from
both `environments/staging` and `environments/production` would produce
two overlapping trails billing and alerting on the same account events.
Convention used in this repo: set `enable_cloudtrail = true` in
**production** only; staging reuses production's trail. If staging and
production live in *separate AWS accounts*, set it `true` in both.

## Example usage

```hcl
module "monitoring" {
  source = "../../modules/monitoring"

  project_name             = "secure-cicd"
  environment              = "production"
  region                   = "us-east-1"
  alert_email              = "you@example.com"
  enable_cloudtrail        = true

  ecs_cluster_name         = module.compute.ecs_cluster_name
  ecs_service_name         = module.compute.ecs_service_name
  alb_arn_suffix           = module.compute.alb_arn_suffix
  target_group_arn_suffix  = module.compute.target_group_arn_suffix
}
```

## Inputs

| Name | Description | Type | Default |
|---|---|---|---|
| `project_name` | Name prefix for all resources | `string` | – |
| `environment` | Environment name | `string` | – |
| `region` | AWS region (for dashboard widgets) | `string` | – |
| `alert_email` | Email to subscribe to the alerts SNS topic | `string` | `null` |
| `enable_cloudtrail` | Create the (account-level) CloudTrail trail | `bool` | `false` |
| `cloudtrail_log_retention_days` | CloudTrail CloudWatch Logs retention | `number` | `365` |
| `ecs_cluster_name` / `ecs_service_name` | From `modules/compute` | `string` | – |
| `alb_arn_suffix` / `target_group_arn_suffix` | From `modules/compute` | `string` | – |
| `alb_5xx_threshold` | 5xx count that triggers an alarm | `number` | `10` |
| `ecs_cpu_alarm_threshold` | CPU % that triggers an alarm | `number` | `85` |
| `tags` | Extra tags merged into all resources | `map(string)` | `{}` |

## Outputs

| Name | Description |
|---|---|
| `sns_topic_arn` | SNS topic ARN for alerts |
| `dashboard_name` | CloudWatch dashboard name |
| `cloudtrail_arn` | Trail ARN (`null` if not created here) |
| `cloudtrail_s3_bucket` | Trail's S3 bucket (`null` if not created here) |
| `cloudtrail_log_group_name` | Trail's CloudWatch Logs group (`null` if not created here) |
