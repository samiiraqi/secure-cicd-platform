variable "project_name" {
  description = "Project name prefix applied to all resources."
  type        = string
  default     = "secure-cicd"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "staging"
}

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs to deploy into."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs for public subnets (one per AZ)."
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs for private subnets (one per AZ)."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "container_port" {
  description = "Port the application container listens on."
  type        = number
  default     = 8080
}

variable "desired_count" {
  description = "Desired number of running ECS tasks."
  type        = number
  default     = 1
}

variable "min_capacity" {
  description = "Minimum ECS tasks for autoscaling."
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum ECS tasks for autoscaling."
  type        = number
  default     = 3
}

variable "alert_email" {
  description = "Email address subscribed to the monitoring SNS topic."
  type        = string
  default     = null
}

variable "alb_ingress_cidrs" {
  description = "CIDR blocks allowed to reach the ALB."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
