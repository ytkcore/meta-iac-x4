# 1. AMI 조회 (Amazon Linux 2023)
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

locals {
  # Name Format: {env}-{project}-{workload}-{resource}-{suffix}
  name_prefix = "${var.env}-${var.project}-${var.name}"

  # AMI selection
  final_ami_id = var.ami_id != null ? var.ami_id : data.aws_ami.al2023.id
}

# 2. IAM Role (기본 신뢰 관계 설정)
resource "aws_iam_role" "this" {
  name = "${local.name_prefix}-role"

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

  tags = {
    Name        = "${local.name_prefix}-role"
    Environment = var.env
  }
}

resource "aws_iam_instance_profile" "this" {
  name = "${local.name_prefix}-profile"
  role = aws_iam_role.this.name
}

# [필수] SSM 접속을 위한 기본 정책 연결
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# 3. EC2 Instance
resource "aws_instance" "this" {
  ami           = local.final_ami_id
  instance_type = var.instance_type
  subnet_id     = var.subnet_id

  vpc_security_group_ids = var.vpc_security_group_ids
  iam_instance_profile   = aws_iam_instance_profile.this.name
  key_name               = var.key_name
  user_data_base64       = var.user_data_base64 != null ? var.user_data_base64 : (var.user_data != null ? base64encode(var.user_data) : null)

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true
  }

  tags = {
    Name        = "${local.name_prefix}-ec2"
    Environment = var.env
    ManagedBy   = "terraform"
  }

  lifecycle {
    ignore_changes = [ami, user_data, user_data_base64]
  }
}
