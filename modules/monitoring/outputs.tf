output "sns_topic_arn" {
  description = "ARN of the SNS topic alarms and CIS security findings are published to."
  value       = aws_sns_topic.alerts.arn
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard."
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail (null when enable_cloudtrail = false)."
  value       = var.enable_cloudtrail ? aws_cloudtrail.this[0].arn : null
}

output "cloudtrail_s3_bucket" {
  description = "S3 bucket holding CloudTrail logs (null when enable_cloudtrail = false)."
  value       = var.enable_cloudtrail ? aws_s3_bucket.trail[0].id : null
}

output "cloudtrail_log_group_name" {
  description = "CloudWatch Logs group receiving CloudTrail events (null when enable_cloudtrail = false)."
  value       = var.enable_cloudtrail ? aws_cloudwatch_log_group.trail[0].name : null
}
