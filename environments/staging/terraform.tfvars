project_name = "secure-cicd"
environment  = "staging"
region       = "us-east-1"

vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

container_port = 8080
desired_count  = 1
min_capacity   = 1
max_capacity   = 3

# Set to your email (or leave null and add an SNS subscription later).
alert_email = null

alb_ingress_cidrs = ["0.0.0.0/0"]
