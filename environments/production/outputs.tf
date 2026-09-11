output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "alb_dns_name" {
  description = "Public DNS name of the ALB - the application URL."
  value       = module.compute.alb_dns_name
}

output "ecr_repository_url" {
  description = "ECR repository URL to push application images to."
  value       = module.compute.ecr_repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = module.compute.ecs_cluster_name
}

output "ecs_service_name" {
  description = "ECS service name."
  value       = module.compute.ecs_service_name
}

output "dashboard_name" {
  description = "CloudWatch dashboard name."
  value       = module.monitoring.dashboard_name
}

output "sns_alert_topic_arn" {
  description = "SNS topic ARN for monitoring/security alerts."
  value       = module.monitoring.sns_topic_arn
}

output "cloudtrail_arn" {
  description = "CloudTrail trail ARN."
  value       = module.monitoring.cloudtrail_arn
}
