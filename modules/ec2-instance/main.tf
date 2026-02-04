# -----------------------------------------------------------------------------
# Golden Image Lookup (from 10-golden-image tfstate)
# -----------------------------------------------------------------------------
data "terraform_remote_state" "golden_image" {
  count = var.ami_id == null && var.state_bucket != null ? 1 : 0
  
  backend = "s3"
  config = {
    bucket  = var.state_bucket
    region  = var.state_region
    key     = "${var.state_key_prefix}/${var.env}/10-golden-image.tfstate"
    encrypt = true
  }
}

# -----------------------------------------------------------------------------
# Fallback: Default AMI (Amazon Linux 2023)
# -----------------------------------------------------------------------------
data "aws_ami" "al2023_fallback" {
  count = var.ami_id == null && var.allow_ami_fallback ? 1 : 0
  
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  
  filter {
    name   = "state"
    values = ["available"]
  }
}

locals {
  # Name Format: {env}-{project}-{workload}-{resource}-{suffix}
  name_prefix = "${var.env}-${var.project}-${var.name}"
  
  # Golden Image AMI from remote state
  golden_ami_id = var.ami_id == null && length(data.terraform_remote_state.golden_image) > 0 ? try(data.terraform_remote_state.golden_image[0].outputs.golden_ami_id, null) : null
  
  # Fallback AMI (AL2023)
  fallback_ami_id = var.ami_id == null && var.allow_ami_fallback && length(data.aws_ami.al2023_fallback) > 0 ? data.aws_ami.al2023_fallback[0].id : null
  
  # AMI Selection Priority:
  # 1. Explicit ami_id (highest priority)
  # 2. Golden Image from remote state
  # 3. Fallback to AL2023 (if allow_ami_fallback=true)
  # 4. Error if none available and fallback disabled
  final_ami_id = var.ami_id != null ? var.ami_id : (
    local.golden_ami_id != null ? local.golden_ami_id : (
      local.fallback_ami_id != null ? local.fallback_ami_id : "ERROR: Golden Image not found and fallback is disabled"
    )
  )

  # Common tags for all resources in this module
  common_tags = {
    Name        = local.name_prefix
    Project     = var.project
    Environment = var.env
    ManagedBy   = "terraform"
  }
  
  # IAM: Use external profile if provided, otherwise create internal
  use_internal_iam = var.iam_instance_profile == null
  final_iam_instance_profile = var.iam_instance_profile != null ? var.iam_instance_profile : (
    local.use_internal_iam ? aws_iam_instance_profile.this[0].name : null
  )
}

# 2. IAM Role (기본 신뢰 관계 설정) - Only if no external profile provided
resource "aws_iam_role" "this" {
  count = local.use_internal_iam ? 1 : 0
  name  = "${local.name_prefix}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-role"
  })
}

resource "aws_iam_instance_profile" "this" {
  count = local.use_internal_iam ? 1 : 0
  name  = "${local.name_prefix}-profile"
  role  = aws_iam_role.this[0].name

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-profile"
  })
}

# [필수] SSM 접속을 위한 기본 정책 연결 - Only if no external profile
resource "aws_iam_role_policy_attachment" "ssm_core" {
  count      = local.use_internal_iam ? 1 : 0
  role       = aws_iam_role.this[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# 3. EC2 Instance
resource "aws_instance" "this" {
  ami           = local.final_ami_id
  instance_type = var.instance_type
  subnet_id     = var.subnet_id

  vpc_security_group_ids = var.vpc_security_group_ids
  iam_instance_profile   = local.final_iam_instance_profile
  key_name               = var.key_name # Standardized to null in Keyless standard
  user_data_base64       = var.user_data_base64 != null ? var.user_data_base64 : (var.user_data != null ? base64encode(var.user_data) : null)

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ec2"
  })

  lifecycle {
    ignore_changes = [ami, user_data, user_data_base64]
  }
}
