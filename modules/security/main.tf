locals {
  name = "${var.project_name}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Module      = "security"
    },
    var.tags
  )
}

# ---------------------------------------------------------------------------
# Security Groups
# ---------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  #checkov:skip=CKV2_AWS_5:attached to aws_lb.this in modules/compute (cross-module reference not resolved by this check)
  name        = "${local.name}-alb-sg"
  description = "Internet-facing ALB: allows inbound HTTP/HTTPS, egress restricted to VPC (forwarded to ECS tasks)."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name}-alb-sg"
  })
}

# This is the internet-facing entry point for a public web app; default is
# 0.0.0.0/0 but alb_ingress_cidrs is a variable specifically so production
# can restrict it (e.g. to a CloudFront/WAF origin or corporate CIDR).
# tfsec:ignore:aws-ec2-no-public-ingress-sgr
resource "aws_security_group_rule" "alb_ingress" {
  for_each = toset([for p in var.alb_ingress_ports : tostring(p)])

  type              = "ingress"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  protocol          = "tcp"
  cidr_blocks       = var.alb_ingress_cidrs
  security_group_id = aws_security_group.alb.id
  description       = "Public ingress on port ${each.value}"
}

resource "aws_security_group_rule" "alb_egress_to_ecs" {
  type                     = "egress"
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_tasks.id
  security_group_id        = aws_security_group.alb.id
  description              = "ALB to ECS tasks on container port"
}

resource "aws_security_group" "ecs_tasks" {
  #checkov:skip=CKV2_AWS_5:attached to aws_ecs_service.app in modules/compute (cross-module reference not resolved by this check)
  name        = "${local.name}-ecs-tasks-sg"
  description = "ECS Fargate tasks: only reachable from the ALB on the container port; broad egress for ECR/CloudWatch/API calls via NAT."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name}-ecs-tasks-sg"
  })
}

resource "aws_security_group_rule" "ecs_ingress_from_alb" {
  type                     = "ingress"
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs_tasks.id
  description              = "ALB to ECS tasks on container port"
}

# Tasks reach ECR, CloudWatch Logs and other AWS APIs over the internet via
# the NAT Gateway; there's no fixed destination IP to scope to. Narrowed to
# 443/tcp (all AWS APIs are HTTPS) instead of all ports/protocols. Replacing
# this with VPC Interface Endpoints for ECR/CloudWatch/S3 would remove the
# need for internet egress entirely - see modules/security/README.md.
# tfsec:ignore:aws-ec2-no-public-egress-sgr
resource "aws_security_group_rule" "ecs_egress_https" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs_tasks.id
  description       = "ECS tasks HTTPS egress (ECR pulls, CloudWatch Logs, AWS API calls via NAT)"
}

# ---------------------------------------------------------------------------
# Network ACLs
# ---------------------------------------------------------------------------

resource "aws_network_acl" "public" {
  #checkov:skip=CKV2_AWS_1:attached via the inline subnet_ids argument below (this check looks for a separate aws_network_acl_association resource)
  vpc_id     = var.vpc_id
  subnet_ids = var.public_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.name}-public-nacl"
  })
}

# Public subnet must accept inbound HTTP from the internet to reach the
# ALB; this is the intended entry point (paired with the SG layer, which
# is the primary control).
# tfsec:ignore:aws-ec2-no-public-ingress-acl
resource "aws_network_acl_rule" "public_in_http" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

# See public_in_http above.
# tfsec:ignore:aws-ec2-no-public-ingress-acl
resource "aws_network_acl_rule" "public_in_https" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

# NACLs are stateless: this allows return traffic (ephemeral ports) for
# connections initiated by clients hitting the ALB, and by NAT-routed
# outbound calls from private subnets. Not a broad allow of application
# ports.
# tfsec:ignore:aws-ec2-no-public-ingress-acl
resource "aws_network_acl_rule" "public_in_ephemeral" {
  #checkov:skip=CKV_AWS_231:ephemeral return-traffic range, not an open port 3389/RDP allow - see comment above
  network_acl_id = aws_network_acl.public.id
  rule_number    = 120
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

# Protocol/port range is "-1" (all) but the source is restricted to
# var.vpc_cidr_block, i.e. intra-VPC traffic only, not the public internet.
# tfsec:ignore:aws-ec2-no-excessive-port-access
resource "aws_network_acl_rule" "public_in_vpc" {
  #checkov:skip=CKV_AWS_352:all-ports but source is var.vpc_cidr_block (intra-VPC only) - see comment above
  network_acl_id = aws_network_acl.public.id
  rule_number    = 130
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr_block
  from_port      = 0
  to_port        = 0
}

# Stateless NACL egress must cover the full ephemeral-port response range
# for any port/protocol a client or upstream service used; Security Groups
# remain the resource-level least-privilege control (see
# aws_security_group.alb).
# tfsec:ignore:aws-ec2-no-excessive-port-access
resource "aws_network_acl_rule" "public_out_all" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 0
  to_port        = 0
}

resource "aws_network_acl" "private" {
  #checkov:skip=CKV2_AWS_1:attached via the inline subnet_ids argument below (this check looks for a separate aws_network_acl_association resource)
  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.name}-private-nacl"
  })
}

# Protocol/port range is "-1" (all) but the source is restricted to
# var.vpc_cidr_block, i.e. intra-VPC traffic only, not the public internet.
# tfsec:ignore:aws-ec2-no-excessive-port-access
resource "aws_network_acl_rule" "private_in_vpc" {
  #checkov:skip=CKV_AWS_352:all-ports but source is var.vpc_cidr_block (intra-VPC only) - see comment above
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr_block
  from_port      = 0
  to_port        = 0
}

# Return traffic for NAT-routed outbound connections initiated from within
# this private subnet (e.g. pulling an image from ECR); not an allow of
# inbound application ports.
# tfsec:ignore:aws-ec2-no-public-ingress-acl
resource "aws_network_acl_rule" "private_in_ephemeral" {
  #checkov:skip=CKV_AWS_231:ephemeral return-traffic range, not an open port 3389/RDP allow - see comment above
  network_acl_id = aws_network_acl.private.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

# Stateless NACL egress must cover the full ephemeral-port response range;
# Security Groups remain the resource-level least-privilege control (see
# aws_security_group_rule.ecs_egress_https, scoped to 443/tcp).
# tfsec:ignore:aws-ec2-no-excessive-port-access
resource "aws_network_acl_rule" "private_out_all" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 0
  to_port        = 0
}
