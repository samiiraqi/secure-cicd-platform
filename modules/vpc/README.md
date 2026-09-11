# modules/vpc

Networking foundation: a VPC with public and private subnets spread across
multiple AZs, an Internet Gateway, NAT Gateway(s) for private-subnet
egress, and VPC Flow Logs shipped to CloudWatch Logs.

## What it creates

- 1 VPC (DNS support + hostnames enabled)
- N public subnets (1 per AZ) + Internet Gateway + public route table
- N private subnets (1 per AZ) + NAT Gateway(s) + private route table(s)
- VPC Flow Logs (`ALL` traffic) to a dedicated, retention-bound,
  KMS-encrypted CloudWatch Logs group, published via a scoped IAM role

## Design notes

- `single_nat_gateway = true` creates one shared NAT Gateway (cheaper —
  recommended for `staging`). Set to `false` for one NAT Gateway per AZ
  (higher availability, higher cost — recommended for `production`).
- No resource here opens anything to the internet by default; that's the
  responsibility of `modules/security` (Security Groups / NACLs) layered
  on top of these subnets.

## Example usage

```hcl
module "vpc" {
  source = "../../modules/vpc"

  project_name          = "secure-cicd"
  environment           = "staging"
  vpc_cidr              = "10.0.0.0/16"
  availability_zones    = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs   = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnet_cidrs  = ["10.0.10.0/24", "10.0.11.0/24"]
  single_nat_gateway    = true
  flow_log_retention_days = 90

  tags = {
    Owner = "platform-team"
  }
}
```

## Inputs

| Name | Description | Type | Default |
|---|---|---|---|
| `project_name` | Name prefix for all resources | `string` | – |
| `environment` | Environment name (staging/production) | `string` | – |
| `vpc_cidr` | VPC CIDR block | `string` | `10.0.0.0/16` |
| `availability_zones` | AZs to deploy into | `list(string)` | – |
| `public_subnet_cidrs` | CIDRs for public subnets | `list(string)` | – |
| `private_subnet_cidrs` | CIDRs for private subnets | `list(string)` | – |
| `single_nat_gateway` | Share one NAT GW vs one per AZ | `bool` | `true` |
| `flow_log_retention_days` | Flow log retention in CloudWatch | `number` | `90` |
| `tags` | Extra tags merged into all resources | `map(string)` | `{}` |

## Outputs

| Name | Description |
|---|---|
| `vpc_id` | VPC ID |
| `vpc_cidr_block` | VPC CIDR |
| `public_subnet_ids` | Public subnet IDs |
| `private_subnet_ids` | Private subnet IDs |
| `nat_gateway_ids` | NAT Gateway ID(s) |
| `internet_gateway_id` | IGW ID |
| `flow_log_group_name` | CloudWatch Logs group name for flow logs |
