variable "project_name" {
  description = "Project/name prefix applied to all resources."
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. staging, production)."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID (from modules/vpc)."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs the ALB is deployed into."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs ECS Fargate tasks are deployed into."
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security Group ID for the ALB (from modules/security)."
  type        = string
}

variable "ecs_tasks_security_group_id" {
  description = "Security Group ID for ECS tasks (from modules/security)."
  type        = string
}

variable "container_port" {
  description = "Port the application container listens on."
  type        = number
  default     = 8080
}

variable "container_image" {
  description = "Container image to run, e.g. '<ecr_repo_url>:latest'. If null, the module's own ECR repository URL is used with the 'latest' tag."
  type        = string
  default     = null
}

variable "task_cpu" {
  description = "Fargate task vCPU units (256 = .25 vCPU). See AWS Fargate valid CPU/memory combinations."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory (MiB)."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Desired number of running tasks."
  type        = number
  default     = 2
}

variable "min_capacity" {
  description = "Minimum tasks for autoscaling."
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum tasks for autoscaling."
  type        = number
  default     = 6
}

variable "cpu_target_utilization" {
  description = "Target average CPU utilization (%) for autoscaling."
  type        = number
  default     = 60
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the ALB HTTPS listener. When set, the ALB listens on 443 (HTTPS) and HTTP (80) redirects to it. When null (default - no domain/cert available), the ALB serves plain HTTP on port 80 only; set this before going to production."
  type        = string
  default     = null
}

variable "health_check_path" {
  description = "HTTP path the ALB target group uses for health checks."
  type        = string
  default     = "/health"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention (days) for container logs."
  type        = number
  default     = 30
}

variable "enable_container_insights" {
  description = "Enable ECS Container Insights on the cluster."
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Enable ALB deletion protection. Defaults to true (safe default); staging sets this false in terraform.tfvars so the environment can be torn down without an extra manual step."
  type        = bool
  default     = true
}

variable "enable_alb_access_logs" {
  description = "Write ALB access logs to a dedicated, encrypted S3 bucket created by this module."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources created by this module."
  type        = map(string)
  default     = {}
}
