terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# 1. IAM Role & Instance Profile
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "teleport" {
  name               = "${var.name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "teleport_policy" {
  # DynamoDB Access
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:CreateTable",
      "dynamodb:BatchWriteItem",
      "dynamodb:DescribeTable",
      "dynamodb:DeleteItem",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:UpdateItem",
      "dynamodb:UpdateTable",
      "dynamodb:DescribeTimeToLive",
      "dynamodb:UpdateTimeToLive",
      "dynamodb:DescribeContinuousBackups",
      "dynamodb:UpdateContinuousBackups",
      "dynamodb:ListTagsOfResource",
      "dynamodb:TagResource",
      "dynamodb:DescribeStream",
      "dynamodb:GetRecords",
      "dynamodb:GetShardIterator",
      "dynamodb:ListStreams"
    ]
    resources = ["*"]
  }

  # S3 Access (Audit Logs)
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:GetBucketVersioning",
      "s3:PutBucketVersioning"
    ]
    resources = [
      aws_s3_bucket.teleport_sessions.arn,
      "${aws_s3_bucket.teleport_sessions.arn}/*"
    ]
  }

  # SSM Access for Debugging
  statement {
    effect = "Allow"
    actions = [
      "ssm:DescribeAssociation",
      "ssm:GetDeployablePatchSnapshotForInstance",
      "ssm:GetDocument",
      "ssm:DescribeDocument",
      "ssm:GetManifest",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:ListAssociations",
      "ssm:ListInstanceAssociations",
      "ssm:PutInventory",
      "ssm:PutComplianceItems",
      "ssm:PutConfigurePackageResult",
      "ssm:UpdateAssociationStatus",
      "ssm:UpdateInstanceAssociationStatus",
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "teleport" {
  name   = "${var.name}-policy"
  role   = aws_iam_role.teleport.id
  policy = data.aws_iam_policy_document.teleport_policy.json
}

resource "aws_iam_instance_profile" "teleport" {
  name = "${var.name}-profile"
  role = aws_iam_role.teleport.name
}

# -----------------------------------------------------------------------------
# 2. Storage
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "teleport_backend" {
  name         = "${var.name}-backend"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "HashKey"
  range_key    = "RangeKey"

  attribute {
    name = "HashKey"
    type = "S"
  }

  attribute {
    name = "RangeKey"
    type = "S"
  }

  ttl {
    attribute_name = "Expires"
    enabled        = true
  }

  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"
  tags             = var.tags
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "teleport_sessions" {
  bucket = "${var.name}-sessions-${var.region}-${data.aws_caller_identity.current.account_id}"
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "teleport_sessions" {
  bucket = aws_s3_bucket.teleport_sessions.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "teleport_sessions" {
  bucket = aws_s3_bucket.teleport_sessions.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "teleport_sessions" {
  bucket = aws_s3_bucket.teleport_sessions.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# 3. Security Group (Applied to EC2)
# -----------------------------------------------------------------------------
resource "aws_security_group" "teleport" {
  name        = "${var.name}-ec2-sg"
  description = "Security Group for Teleport EC2 Instances"
  vpc_id      = var.vpc_id

  # Allow Traffic from ALB
  ingress {
    from_port       = 3080
    to_port         = 3080
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
    description     = "Allow Web UI from ALB"
  }

  # Allow Tunnel from VPC (for internal agents)
  ingress {
    from_port   = 3024
    to_port     = 3024
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Allow Reverse Tunnel from VPC"
  }

  # Allow Web from VPC (for internal connectivity)
  ingress {
    from_port   = 3080
    to_port     = 3080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Allow Web UI from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-ec2-sg" })
}

# -----------------------------------------------------------------------------
# 4. Load Balancer Routing (Target Groups & Rules)
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "web" {
  name     = "${var.name}-web-tg"
  port     = 3080
  protocol = "HTTPS"
  vpc_id   = var.vpc_id

  # HTTP1 - Teleport's ALPN only accepts HTTP/1.1
  # gRPC connections use WebSocket upgrade over HTTP/1.1
  protocol_version = "HTTP1"

  health_check {
    path                = "/webapi/ping"
    protocol            = "HTTPS"
    matcher             = "200"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = var.tags
}



# Rule 1: gRPC Traffic -> gRPC TG


# Rule 2: Default Web Traffic -> Web TG (Catch-all for this domain)
resource "aws_lb_listener_rule" "web" {
  listener_arn = var.listener_arn
  priority     = 60

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  condition {
    host_header {
      values = [var.domain_name, "*.${var.domain_name}"]
    }
  }
}
