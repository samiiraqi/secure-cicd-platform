output "alb_security_group_id" {
  description = "Security Group ID for the ALB."
  value       = aws_security_group.alb.id
}

output "ecs_tasks_security_group_id" {
  description = "Security Group ID for ECS Fargate tasks."
  value       = aws_security_group.ecs_tasks.id
}

output "public_nacl_id" {
  description = "Network ACL ID associated with public subnets."
  value       = aws_network_acl.public.id
}

output "private_nacl_id" {
  description = "Network ACL ID associated with private subnets."
  value       = aws_network_acl.private.id
}
