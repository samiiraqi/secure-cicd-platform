variable "project_name" {
  description = "Project/name prefix applied to all resources (e.g. secure-cicd)."
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. staging, production). Used in resource naming and tags."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs to spread subnets across. Must have at least 2 for HA."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets, one per AZ (same order as availability_zones)."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets, one per AZ (same order as availability_zones)."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "If true, create a single NAT Gateway shared by all private subnets (cheaper, less resilient). If false, one NAT Gateway per AZ. Recommended: true for staging, false for production."
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "Retention period (days) for VPC Flow Logs in CloudWatch Logs. Defaults to 1 year - this is an audit/security log, not app debug output."
  type        = number
  default     = 365
}

variable "tags" {
  description = "Additional tags to apply to all resources created by this module."
  type        = map(string)
  default     = {}
}
