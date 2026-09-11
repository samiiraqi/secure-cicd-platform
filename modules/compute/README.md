# modules/compute

Runs the application on ECS Fargate behind an ALB, with its own ECR
repository. Encapsulates everything needed to go from "container image"
to "publicly reachable, autoscaled service."

## What it creates

- **ECR repository** — immutable tags, `scan_on_push` (Trivy/CI adds a
  second scan pre-deploy; this catches anything pushed directly), KMS
  encryption at rest, lifecycle policy expiring untagged images after 14
  days.
- **KMS key** — encrypts the ECR repository and the container CloudWatch
  Logs group, with rotation enabled.
- **ECS Cluster** — Fargate, Container Insights enabled by default.
- **IAM roles** — a task *execution* role (pull image, write logs, decrypt
  via KMS — scoped to this service) separate from the task *runtime* role
  (starts empty; extend it with only what the application needs).
- **ALB + target group + HTTP listener** — health-checked target group
  (`target_type = ip`, required for Fargate), deletion protection on by
  default, access logs to a dedicated encrypted S3 bucket.
- **ECS Task Definition + Service** — `awsvpc` networking in private
  subnets, `readonlyRootFilesystem`, no public IP, `enable_execute_command
  = false`.
- **Application Auto Scaling** — target-tracking on average CPU
  utilization.

## Design notes

- The running task definition is excluded from Terraform's plan diff
  (`lifecycle.ignore_changes`) so the CI/CD pipeline can deploy new image
  tags (`aws ecs update-service` / a deploy action) without every
  subsequent `terraform plan` showing a false-positive change.
- `container_image` defaults to `<this module's ECR repo>:latest` if not
  set — point it at a specific digest/tag for reproducible deploys.
- The task role is deliberately empty by default; attach only the
  permissions the application actually calls (least privilege) rather
  than a broad managed policy.
- The ALB serves plain HTTP by default (no domain/certificate available
  out of the box). Pass `certificate_arn` (an ACM cert) to get an HTTPS
  listener on 443 with the HTTP listener redirecting to it - do this
  before serving real traffic.

## Example usage

```hcl
module "compute" {
  source = "../../modules/compute"

  project_name                 = "secure-cicd"
  environment                  = "staging"
  vpc_id                       = module.vpc.vpc_id
  public_subnet_ids            = module.vpc.public_subnet_ids
  private_subnet_ids           = module.vpc.private_subnet_ids
  alb_security_group_id        = module.security.alb_security_group_id
  ecs_tasks_security_group_id  = module.security.ecs_tasks_security_group_id
  container_port               = 8080
  desired_count                = 2
}
```

## Inputs

| Name | Description | Type | Default |
|---|---|---|---|
| `project_name` | Name prefix for all resources | `string` | – |
| `environment` | Environment name | `string` | – |
| `vpc_id` | VPC ID | `string` | – |
| `public_subnet_ids` | Public subnets for the ALB | `list(string)` | – |
| `private_subnet_ids` | Private subnets for ECS tasks | `list(string)` | – |
| `alb_security_group_id` | ALB Security Group ID | `string` | – |
| `ecs_tasks_security_group_id` | ECS tasks Security Group ID | `string` | – |
| `container_port` | App container port | `number` | `8080` |
| `container_image` | Image to run (defaults to this module's ECR `:latest`) | `string` | `null` |
| `certificate_arn` | ACM cert ARN; enables HTTPS listener + HTTP->HTTPS redirect | `string` | `null` |
| `task_cpu` / `task_memory` | Fargate task size | `number` | `256` / `512` |
| `desired_count` | Initial task count | `number` | `2` |
| `min_capacity` / `max_capacity` | Autoscaling bounds | `number` | `2` / `6` |
| `cpu_target_utilization` | Target CPU % for autoscaling | `number` | `60` |
| `health_check_path` | ALB health check path | `string` | `/health` |
| `log_retention_days` | Container log retention | `number` | `30` |
| `enable_container_insights` | Toggle Container Insights | `bool` | `true` |
| `enable_deletion_protection` | ALB deletion protection | `bool` | `true` |
| `enable_alb_access_logs` | Write ALB access logs to a dedicated S3 bucket | `bool` | `true` |
| `tags` | Extra tags merged into all resources | `map(string)` | `{}` |

## Outputs

| Name | Description |
|---|---|
| `ecr_repository_url` | ECR repository URL (push images here) |
| `ecs_cluster_name` | ECS cluster name |
| `ecs_service_name` | ECS service name |
| `alb_dns_name` | Public ALB DNS name |
| `alb_arn_suffix` / `target_group_arn_suffix` | For CloudWatch metrics/alarms |
| `task_execution_role_arn` / `task_role_arn` | IAM role ARNs |
| `container_log_group_name` | CloudWatch Logs group for container logs |
