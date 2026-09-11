project_name = "secure-cicd"
environment  = "production"
region       = "us-east-1"

vpc_cidr             = "10.1.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
public_subnet_cidrs  = ["10.1.0.0/24", "10.1.1.0/24", "10.1.2.0/24"]
private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24", "10.1.12.0/24"]

container_port = 8080
desired_count  = 3
min_capacity   = 3
max_capacity   = 10

# Set to a real, monitored address before applying to production.
alert_email = null

# TODO: restrict before going live (e.g. to a WAF/CloudFront origin or
# corporate CIDR) instead of leaving the ALB open to the internet.
alb_ingress_cidrs = ["0.0.0.0/0"]
