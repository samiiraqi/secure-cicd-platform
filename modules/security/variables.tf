variable "project_name" {
  description = "Project/name prefix applied to all resources."
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. staging, production)."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID (from modules/vpc) to attach Security Groups and NACLs to."
  type        = string
}

variable "vpc_cidr_block" {
  description = "CIDR block of the VPC (from modules/vpc), used for internal-only rules."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs to associate with the public NACL."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs to associate with the private NACL."
  type        = list(string)
}

variable "alb_ingress_cidrs" {
  description = "CIDR blocks allowed to reach the ALB on ingress_ports. Restrict this for production (e.g. a corporate CIDR or WAF-fronted setup)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "alb_ingress_ports" {
  description = "Ports the ALB Security Group accepts inbound traffic on."
  type        = list(number)
  default     = [80, 443]
}

variable "container_port" {
  description = "Port the application container listens on; only the ALB Security Group may reach ECS tasks on this port."
  type        = number
  default     = 8080
}

variable "tags" {
  description = "Additional tags to apply to all resources created by this module."
  type        = map(string)
  default     = {}
}
