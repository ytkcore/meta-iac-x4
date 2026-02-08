# =============================================================================
# Teleport EC2 Module
# 
# Teleport Auth/Proxy/Node All-in-one 구성
# - DynamoDB Backend (Cluster State)
# - S3 Backend (Session Recordings)
# - IAM Role & Instance Profile
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# 1. IAM Role & Policy
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
  # DynamoDB Access - Full permissions required by Teleport
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
      # Additional permissions required by Teleport
      "dynamodb:DescribeTimeToLive",
      "dynamodb:UpdateTimeToLive",
      "dynamodb:DescribeContinuousBackups",
      "dynamodb:UpdateContinuousBackups",
      "dynamodb:ListTagsOfResource",
      "dynamodb:TagResource",
      # Stream permissions
      "dynamodb:DescribeStream",
      "dynamodb:GetRecords",
      "dynamodb:GetShardIterator",
      "dynamodb:ListStreams"
    ]
    resources = [
      aws_dynamodb_table.teleport_backend.arn,
      "${aws_dynamodb_table.teleport_backend.arn}/stream/*"
    ]
  }

  # S3 Access (Audit Logs)
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:GetBucketVersioning",
      "s3:PutBucketVersioning" # 초기 설정용
    ]
    resources = [
      aws_s3_bucket.teleport_sessions.arn,
      "${aws_s3_bucket.teleport_sessions.arn}/*"
    ]
  }

  # Session Manager (SSM) Access - for debugging
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

resource "aws_iam_instance_profile" "teleport" {
  name = "${var.name}-profile"
  role = aws_iam_role.teleport.name
}

# -----------------------------------------------------------------------------
# 2. Storage (DynamoDB & S3)
# -----------------------------------------------------------------------------

# DynamoDB for Cluster State
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

  # TTL (Optional, but good practice)
  ttl {
    attribute_name = "Expires"
    enabled        = true
  }

  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"

  tags = var.tags
}

# S3 for Session Recordings
resource "aws_s3_bucket" "teleport_sessions" {
  bucket = "${var.name}-sessions-${var.region}-${data.aws_caller_identity.current.account_id}"
  # force_destroy = false # 안전을 위해 false 권장

  tags = var.tags
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

# Block Public Access
resource "aws_s3_bucket_public_access_block" "teleport_sessions" {
  bucket = aws_s3_bucket.teleport_sessions.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# 3. Security Group
# -----------------------------------------------------------------------------
resource "aws_security_group" "teleport" {
  name        = "${var.name}-sg"
  description = "Security Group for Teleport Server"
  vpc_id      = var.vpc_id

  # Inbound: ALB (3080, 3023, 3024?), or direct?
  # Teleport Default Ports:
  # 3023: SSH Proxy
  # 3024: SSH Tunnel (Reverse Tunnel)
  # 3025: Auth Service (gRPC)
  # 3080: Web UI / Proxy (HTTPS)

  # ALB를 통해 들어오는 Web UI (3080)
  ingress {
    from_port       = 3080
    to_port         = 3080
    protocol        = "tcp"
    security_groups = var.alb_security_group_ids
    description     = "Allow Web UI from ALB"
  }

  # ALB를 통해 들어오는 Tunnel (3023, 3024 등도 필요할 수 있음. ALB 구성에 따라 다름)
  # Tunnel(3024)은 ALB가 아니라 NLB가 필요한 경우가 많지만, WebSockets over ALB도 가능.
  # 여기서는 443(ALB) -> 3080(EC2) 만 먼저 고려.

  # SSH (Optional for debugging via Bastion or VPN) - 여기서는 SSM만 사용 권장

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all egress"
  }

  tags = merge(var.tags, { Name = "${var.name}-sg" })
}

# -----------------------------------------------------------------------------
# 4. EC2 Instance (using ec2-instance module for Golden Image support)
# -----------------------------------------------------------------------------
locals {
  instance_count = var.enable_ha ? 2 : 1
  
  # User data for Teleport installation
  user_data = templatefile("${path.module}/user-data.sh", {
    cluster_name     = var.cluster_name
    region           = var.region
    dynamo_table     = aws_dynamodb_table.teleport_backend.name
    s3_bucket        = aws_s3_bucket.teleport_sessions.id
    email            = var.email
    teleport_version = var.teleport_version
  })
}

module "instance" {
  source = "../ec2-instance"
  count  = local.instance_count

  name    = "teleport-${count.index + 1}"
  env     = var.env
  project = var.project
  region  = var.region

  subnet_id              = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids = [aws_security_group.teleport.id]
  instance_type          = var.instance_type
  root_volume_size       = 50

  user_data = local.user_data

  # Golden Image State Configuration
  state_bucket       = var.state_bucket
  state_region       = var.state_region
  state_key_prefix   = var.state_key_prefix
  ami_id             = var.ami_id  # Optional override
  allow_ami_fallback = var.allow_ami_fallback
}

# Attach Teleport policy to ec2-instance module's IAM role (inline policy)
resource "aws_iam_role_policy" "teleport_to_ec2_instance" {
  count  = local.instance_count
  name   = "${var.name}-teleport-policy"
  role   = module.instance[count.index].iam_role_name
  policy = data.aws_iam_policy_document.teleport_policy.json
}
