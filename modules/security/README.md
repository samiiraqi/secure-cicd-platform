# modules/security

Security Groups and Network ACLs implementing least-privilege network
access between the internet, the ALB, and the ECS Fargate tasks.

## What it creates

- **ALB Security Group** — ingress on `alb_ingress_ports` (default 80/443)
  from `alb_ingress_cidrs`; egress restricted to the ECS tasks SG on
  `container_port` only.
- **ECS Tasks Security Group** — ingress on `container_port` from the ALB
  SG *only* (no direct internet or public access to tasks); broad egress
  (needed for ECR image pulls, CloudWatch Logs, and other AWS API calls
  routed out through the NAT Gateway).
- **Public NACL** — explicit allow rules for HTTP/HTTPS ingress, ephemeral
  return-traffic ports, and intra-VPC traffic; all egress allowed.
- **Private NACL** — allow intra-VPC ingress and ephemeral return traffic;
  all egress allowed (required for outbound-only NAT traffic).

## Design notes

- Defense in depth: Security Groups (stateful, resource-level) *and*
  NACLs (stateless, subnet-level) are both defined, rather than relying
  on the default "allow all" NACL.
- ECS tasks are **never** directly reachable from the internet — all
  inbound traffic must traverse the ALB.
- For production, tighten `alb_ingress_cidrs` (e.g. restrict to a WAF /
  CloudFront origin, or a corporate range) instead of `0.0.0.0/0`.
- ECS task egress is narrowed to 443/tcp (all AWS APIs are HTTPS) rather
  than all ports/protocols, but the destination is still `0.0.0.0/0`
  because traffic leaves via the NAT Gateway to reach ECR/CloudWatch/AWS
  APIs with no fixed IP to scope to. A stronger-still option: add VPC
  Interface Endpoints for ECR, CloudWatch Logs and S3, and scope egress to
  just those endpoints/the VPC CIDR, removing the need for internet egress
  entirely.
- A handful of rules here (public ingress on 80/443, NACL ephemeral-port
  ranges, stateless NACL egress) are flagged CRITICAL/HIGH by tfsec by
  design — they're inherent to running a public-facing ALB with stateless
  NACLs. Each is annotated inline with `tfsec:ignore:<rule-id>` and a
  justification rather than silently suppressed.

## Example usage

```hcl
module "security" {
  source = "../../modules/security"

  project_name        = "secure-cicd"
  environment         = "staging"
  vpc_id              = module.vpc.vpc_id
  vpc_cidr_block      = module.vpc.vpc_cidr_block
  public_subnet_ids   = module.vpc.public_subnet_ids
  private_subnet_ids  = module.vpc.private_subnet_ids
  container_port      = 8080
  alb_ingress_cidrs   = ["0.0.0.0/0"]
}
```

## Inputs

| Name | Description | Type | Default |
|---|---|---|---|
| `project_name` | Name prefix for all resources | `string` | – |
| `environment` | Environment name | `string` | – |
| `vpc_id` | VPC ID from `modules/vpc` | `string` | – |
| `vpc_cidr_block` | VPC CIDR from `modules/vpc` | `string` | – |
| `public_subnet_ids` | Public subnet IDs | `list(string)` | – |
| `private_subnet_ids` | Private subnet IDs | `list(string)` | – |
| `alb_ingress_cidrs` | CIDRs allowed to reach the ALB | `list(string)` | `["0.0.0.0/0"]` |
| `alb_ingress_ports` | Ports the ALB accepts | `list(number)` | `[80, 443]` |
| `container_port` | App container port (ALB -> ECS) | `number` | `8080` |
| `tags` | Extra tags merged into all resources | `map(string)` | `{}` |

## Outputs

| Name | Description |
|---|---|
| `alb_security_group_id` | ALB Security Group ID |
| `ecs_tasks_security_group_id` | ECS tasks Security Group ID |
| `public_nacl_id` | Public NACL ID |
| `private_nacl_id` | Private NACL ID |
