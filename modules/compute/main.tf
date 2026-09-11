locals {
  name = "${var.project_name}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Module      = "compute"
    },
    var.tags
  )

  container_image = coalesce(var.container_image, "${aws_ecr_repository.app.repository_url}:latest")
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# KMS key - encrypts ECR images and container CloudWatch Logs at rest
# ---------------------------------------------------------------------------

resource "aws_kms_key" "compute" {
  description             = "${local.name} compute encryption key (ECR, container logs)"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name = "${local.name}-compute-kms"
  })
}

resource "aws_kms_alias" "compute" {
  name          = "alias/${local.name}-compute"
  target_key_id = aws_kms_key.compute.key_id
}

data "aws_iam_policy_document" "kms" {
  #checkov:skip=CKV_AWS_109:this is a KMS key policy, not an IAM identity policy - "Resource":"*" scopes to "this key" per AWS's own key-policy model
  #checkov:skip=CKV_AWS_111:same as CKV_AWS_109 above
  #checkov:skip=CKV_AWS_356:same as CKV_AWS_109 above
  statement {
    sid       = "EnableRootAccountAccess"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid    = "AllowECRService"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["ecr.amazonaws.com"]
    }
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.name}.amazonaws.com"]
    }
  }
}

resource "aws_kms_key_policy" "compute" {
  key_id = aws_kms_key.compute.id
  policy = data.aws_iam_policy_document.kms.json
}

# ---------------------------------------------------------------------------
# ECR - image repository with scan-on-push and encryption at rest
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  name                 = "${local.name}-app"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.compute.arn
  }

  tags = local.common_tags
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 14 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# CloudWatch Logs (container stdout/stderr), encrypted with the KMS key
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "app" {
  #checkov:skip=CKV_AWS_338:operational app logs, deliberately kept short (default 30d) to control cost - audit-relevant logs (CloudTrail, VPC Flow Logs) already retain >=365d by default
  name              = "/ecs/${local.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.compute.arn

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# ECS Cluster
# ---------------------------------------------------------------------------

resource "aws_ecs_cluster" "this" {
  name = local.name

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# IAM - task execution role (pull image, write logs) and task role
# (application runtime permissions), each scoped to this service only.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${local.name}-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# "GenerateDataKey*" is AWS's own recommended action pattern (covers
# GenerateDataKey / GenerateDataKeyWithoutPlaintext); the resource is
# scoped to this module's single KMS key ARN, not a wildcard resource.
# tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "task_execution_kms" {
  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
    ]
    resources = [aws_kms_key.compute.arn]
  }
}

resource "aws_iam_role_policy" "task_execution_kms" {
  name   = "${local.name}-task-execution-kms"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution_kms.json
}

resource "aws_iam_role" "task" {
  name               = "${local.name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json

  tags = local.common_tags
}

# Intentionally minimal by default: extend with additional
# aws_iam_role_policy / aws_iam_role_policy_attachment resources scoped to
# only what the application actually needs (least privilege).

# ---------------------------------------------------------------------------
# ALB access logs bucket (S3 access-log destinations require SSE-S3, not
# SSE-KMS, per AWS - a separate, purpose-built bucket rather than reusing
# the KMS-encrypted compute/monitoring buckets).
# ---------------------------------------------------------------------------

# This bucket IS the log destination (ALB access logs); logging the log
# bucket itself isn't meaningful.
# tfsec:ignore:aws-s3-enable-bucket-logging
resource "aws_s3_bucket" "alb_logs" {
  #checkov:skip=CKV_AWS_144:access-log archive for a single-region demo deployment; cross-region replication is unnecessary cost/complexity here
  #checkov:skip=CKV2_AWS_62:access logs don't need their own event notifications; this bucket IS the log destination
  #checkov:skip=CKV_AWS_18:this bucket holds ALB access logs; enabling access logging on the access-log bucket itself is not meaningful
  #checkov:skip=CKV_AWS_145:ALB access log delivery only supports SSE-S3, not SSE-KMS (AWS platform limitation) - see aws_s3_bucket_server_side_encryption_configuration.alb_logs
  #checkov:skip=CKV_AWS_21:versioning IS enabled - see aws_s3_bucket_versioning.alb_logs below. Verified via isolated repro that this is a checkov graph-resolution limitation with count-conditional buckets, not a real gap.
  #checkov:skip=CKV2_AWS_6:a Public Access block IS attached - see aws_s3_bucket_public_access_block.alb_logs below. Same checkov limitation as CKV_AWS_21 above.
  #checkov:skip=CKV2_AWS_61:a lifecycle configuration IS attached - see aws_s3_bucket_lifecycle_configuration.alb_logs below. Same checkov limitation as CKV_AWS_21 above.
  count         = var.enable_alb_access_logs ? 1 : 0
  bucket        = "${local.name}-alb-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = false

  tags = local.common_tags
}

resource "aws_s3_bucket_versioning" "alb_logs" {
  count  = var.enable_alb_access_logs ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

# ALB access log delivery only supports SSE-S3, not SSE-KMS (an AWS
# platform limitation, not a choice made here) - see the comment above
# this section.
# tfsec:ignore:aws-s3-encryption-customer-key
resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  count  = var.enable_alb_access_logs ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  count  = var.enable_alb_access_logs ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  count  = var.enable_alb_access_logs ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  rule {
    id     = "expire-old-access-logs"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    expiration {
      days = 90
    }
  }
}

data "aws_iam_policy_document" "alb_logs" {
  count = var.enable_alb_access_logs ? 1 : 0

  statement {
    sid       = "AllowALBLogDelivery"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alb_logs[0].arn}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  count  = var.enable_alb_access_logs ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id
  policy = data.aws_iam_policy_document.alb_logs[0].json
}

# ---------------------------------------------------------------------------
# ALB
# ---------------------------------------------------------------------------

# This is deliberately an internet-facing ALB (the entry point for a
# public web app); ECS tasks behind it stay in private subnets with no
# public IP (see aws_ecs_service.app). Restrict exposure via
# alb_ingress_cidrs and/or a WAF/CloudFront origin instead of making the
# ALB internal. Attaching a WAF Web ACL (CKV2_AWS_28) is left as an
# optional layer on top of this module rather than a hard dependency.
# tfsec:ignore:aws-elb-alb-not-public
resource "aws_lb" "this" {
  #checkov:skip=CKV2_AWS_28:WAF is an optional layer on top of this module, not a hard dependency - see comment above
  #checkov:skip=CKV_AWS_150:configurable via enable_deletion_protection (defaults true); staging intentionally sets it false in environments/staging/main.tf so `terraform destroy` needs no manual pre-step
  #checkov:skip=CKV2_AWS_20:the HTTP listener redirects to HTTPS once certificate_arn is set - see aws_lb_listener.http and aws_lb_listener.https below. No ACM cert is available by default.
  name               = "${local.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  drop_invalid_header_fields = true
  enable_deletion_protection = var.enable_deletion_protection

  dynamic "access_logs" {
    for_each = var.enable_alb_access_logs ? [1] : []
    content {
      bucket  = aws_s3_bucket.alb_logs[0].id
      prefix  = "alb"
      enabled = true
    }
  }

  tags = local.common_tags

  depends_on = [aws_s3_bucket_policy.alb_logs]
}

resource "aws_lb_target_group" "app" {
  #checkov:skip=CKV_AWS_378:TLS terminates at the ALB (see aws_lb_listener.https below when certificate_arn is set); backend traffic to tasks stays inside the VPC over the ECS tasks SG
  name        = "${local.name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = var.health_check_path
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200-299"
  }

  tags = local.common_tags
}

# Plain HTTP by default because this module has no domain/ACM certificate
# to attach out of the box. Set var.certificate_arn to switch this
# listener to a 443 redirect and enable the HTTPS listener below - do this
# before serving real traffic.
# tfsec:ignore:aws-elb-http-not-used
resource "aws_lb_listener" "http" {
  #checkov:skip=CKV_AWS_2:no ACM cert available by default - set var.certificate_arn to enable HTTPS (see comment above)
  #checkov:skip=CKV_AWS_103:same as CKV_AWS_2 above - TLS policy only applies once certificate_arn is set
  #checkov:skip=CKV2_AWS_20:this listener forwards to HTTP only when certificate_arn is null; it redirects to the HTTPS listener once one is set
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = var.certificate_arn != null ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = var.certificate_arn == null ? [1] : []
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.app.arn
    }
  }
}

resource "aws_lb_listener" "https" {
  count = var.certificate_arn != null ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ---------------------------------------------------------------------------
# ECS Task Definition + Service (Fargate)
# ---------------------------------------------------------------------------

resource "aws_ecs_task_definition" "app" {
  family                   = local.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = local.container_image
      essential = true
      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "app"
        }
      }
      readonlyRootFilesystem = true
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "app" {
  name            = "${local.name}-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  enable_execute_command = false

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_tasks_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  depends_on = [aws_lb_listener.http]

  tags = local.common_tags

  lifecycle {
    ignore_changes = [task_definition] # allow CI/CD to update the running image without a plan diff every apply
  }
}

# ---------------------------------------------------------------------------
# Autoscaling
# ---------------------------------------------------------------------------

resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${local.name}-cpu-target-tracking"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = var.cpu_target_utilization
  }
}
