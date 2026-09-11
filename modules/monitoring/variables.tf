variable "project_name" {
  description = "Project/name prefix applied to all resources."
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. staging, production)."
  type        = string
}

variable "region" {
  description = "AWS region, used to build dashboard widget queries."
  type        = string
}

variable "alert_email" {
  description = "Email address subscribed to the security/operational SNS alert topic. Leave null to skip creating a subscription (you can add one later)."
  type        = string
  default     = null
}

variable "enable_cloudtrail" {
  description = "Whether this module should create the CloudTrail trail. CloudTrail (multi-region, this account) should only be created ONCE per AWS account — typically true in production and false in staging, so staging reuses production's trail/alarms rather than creating a duplicate."
  type        = bool
  default     = false
}

variable "cloudtrail_log_retention_days" {
  description = "Retention period (days) for the CloudTrail CloudWatch Logs group."
  type        = number
  default     = 365
}

variable "ecs_cluster_name" {
  description = "ECS cluster name (from modules/compute), for dashboard widgets."
  type        = string
}

variable "ecs_service_name" {
  description = "ECS service name (from modules/compute), for dashboard widgets."
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix (from modules/compute), for dashboard widgets/alarms."
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix (from modules/compute), for dashboard widgets/alarms."
  type        = string
}

variable "alb_5xx_threshold" {
  description = "Number of ALB 5xx responses in one evaluation period that triggers an alarm."
  type        = number
  default     = 10
}

variable "ecs_cpu_alarm_threshold" {
  description = "ECS service average CPU utilization (%) that triggers a high-CPU alarm."
  type        = number
  default     = 85
}

variable "tags" {
  description = "Additional tags to apply to all resources created by this module."
  type        = map(string)
  default     = {}
}
