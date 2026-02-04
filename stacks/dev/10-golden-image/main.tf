# =============================================================================
# 10-golden-image Stack
# Golden Image (AMI) 빌드 및 관리
# =============================================================================

provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------
locals {
  name_prefix = "${var.project}-${var.env}-golden-image"
  
  common_tags = {
    ManagedBy   = "terraform"
    Project     = var.project
    Environment = var.env
    Stack       = "10-golden-image"
  }
  
  # 골든 이미지 이름 패턴
  ami_name_pattern = "meta-golden-image-al2023-*"
  
  # 타임스탬프 (AMI 이름용)
  timestamp = formatdate("YYYYMMDD-hhmmss", timestamp())
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

# 최신 Amazon Linux 2023 AMI (Base Image)
data "aws_ami" "al2023_base" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# 기존 Golden Image 조회 (있다면)
data "aws_ami" "golden_existing" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = [local.ami_name_pattern]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# -----------------------------------------------------------------------------
# Golden Image Configuration (Packer용 참조 or EC2 Image Builder용)
# -----------------------------------------------------------------------------

# 골든 이미지 설정값 (스택별 On/Off 제어에 사용)
# 실제 AMI 빌드는 Packer 또는 EC2 Image Builder로 수행
#
# 이 설정값들은:
# 1. 문서화 용도 (golden-image-specification.md 참조)
# 2. user-data에서 동적으로 활성화/비활성화하는 기준
# 3. Packer 템플릿에 변수로 전달 가능

locals {
  # 골든 이미지 기본 포함 항목 (On/Off 설정)
  golden_image_config = {
    # Container Runtime
    docker = {
      installed = true
      enabled   = true  # 기본 활성화 (60-db, 40-harbor에서 사용)
      version   = "24.x"
    }
    docker_compose = {
      installed = true
      version   = "2.x"
    }
    
    # AWS Agents
    ssm_agent = {
      installed = true
      enabled   = true  # 항상 활성화 (Break Glass 필수)
    }
    cloudwatch_agent = {
      installed = true
      enabled   = false  # 기본 비활성화 (비용 최적화)
      # Dev: Teleport, DB만 활성화
      # Prod: 전체 활성화 권장
    }
    
    # Access Control
    teleport_agent = {
      installed = true
      enabled   = false  # 기본 비활성화 (스택별 user-data에서 제어)
    }
    
    # SSH Configuration
    ssh = {
      port                     = 22  # 기본값 (make init에서 변경 가능)
      password_authentication  = false
      permit_root_login        = false
      max_auth_tries           = 3
    }
    
    # Security
    selinux = {
      enabled = true
      mode    = "enforcing"
    }
  }
  
}

# -----------------------------------------------------------------------------
# SSM Parameter Store (설정 공유용)
# -----------------------------------------------------------------------------

# SSH 포트 설정 (모든 스택에서 참조 가능)
resource "aws_ssm_parameter" "ssh_port" {
  name        = "/${var.env}/${var.project}/golden-image/ssh-port"
  description = "Golden Image SSH Port Configuration"
  type        = "String"
  value       = tostring(var.ssh_port)
  
  tags = local.common_tags
}

# CloudWatch 활성화 설정
resource "aws_ssm_parameter" "cloudwatch_enabled" {
  name        = "/${var.env}/${var.project}/golden-image/cloudwatch-enabled"
  description = "CloudWatch Agent default enabled state"
  type        = "String"
  value       = tostring(var.cloudwatch_agent_enabled)
  
  tags = local.common_tags
}

# Teleport 활성화 설정
resource "aws_ssm_parameter" "teleport_enabled" {
  name        = "/${var.env}/${var.project}/golden-image/teleport-enabled"
  description = "Teleport Agent default enabled state"
  type        = "String"
  value       = tostring(var.teleport_agent_enabled)
  
  tags = local.common_tags
}

# Docker 활성화 설정
resource "aws_ssm_parameter" "docker_enabled" {
  name        = "/${var.env}/${var.project}/golden-image/docker-enabled"
  description = "Docker default enabled state"
  type        = "String"
  value       = tostring(var.docker_enabled)
  
  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Outputs (다른 스택에서 참조)
# -----------------------------------------------------------------------------
# outputs.tf 파일로 분리
