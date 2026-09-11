module "vpc" {
  source = "../../modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  # Production: one NAT Gateway per AZ for high availability.
  single_nat_gateway = false
}

module "security" {
  source = "../../modules/security"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  vpc_cidr_block     = module.vpc.vpc_cidr_block
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  container_port     = var.container_port
  alb_ingress_cidrs  = var.alb_ingress_cidrs
}

module "compute" {
  source = "../../modules/compute"

  project_name                = var.project_name
  environment                 = var.environment
  vpc_id                      = module.vpc.vpc_id
  public_subnet_ids           = module.vpc.public_subnet_ids
  private_subnet_ids          = module.vpc.private_subnet_ids
  alb_security_group_id       = module.security.alb_security_group_id
  ecs_tasks_security_group_id = module.security.ecs_tasks_security_group_id
  container_port              = var.container_port

  task_cpu      = 512
  task_memory   = 1024
  desired_count = var.desired_count
  min_capacity  = var.min_capacity
  max_capacity  = var.max_capacity
}

module "monitoring" {
  source = "../../modules/monitoring"

  project_name = var.project_name
  environment  = var.environment
  region       = var.region
  alert_email  = var.alert_email

  # Production owns the account-level CloudTrail trail - see
  # modules/monitoring/README.md ("why enable_cloudtrail is a toggle").
  enable_cloudtrail = true

  ecs_cluster_name        = module.compute.ecs_cluster_name
  ecs_service_name        = module.compute.ecs_service_name
  alb_arn_suffix          = module.compute.alb_arn_suffix
  target_group_arn_suffix = module.compute.target_group_arn_suffix
}
