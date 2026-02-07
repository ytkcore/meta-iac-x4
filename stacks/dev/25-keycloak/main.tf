# ==============================================================================
# 25-keycloak Stack
#
# Description:
#   Keycloak Identity Provider — SSO + Workload OIDC
#   - Docker Compose 기반 (Golden Image EC2)
#   - 외부 PostgreSQL (60-postgres) 연동
#   - Private DNS: keycloak.dev.unifiedmeta.net
#
# Dependencies:
#   - 00-network (VPC, Subnets)
#   - 05-security (SG clients)
#   - 60-postgres (DB)
#   - 50-rke2 (K8s 노드 SG, OIDC 연동)
# ==============================================================================

provider "aws" {
  region = var.region
}

locals {
  name = "${var.project}-${var.env}-keycloak"
  common_tags = {
    ManagedBy   = "terraform"
    Project     = var.project
    Environment = var.env
    Stack       = "25-keycloak"
  }
}

# ------------------------------------------------------------------------------
# Remote State
# ------------------------------------------------------------------------------

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.state_region
    key    = "${var.state_key_prefix}/${var.env}/00-network.tfstate"
  }
}

data "terraform_remote_state" "security" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.state_region
    key    = "${var.state_key_prefix}/${var.env}/05-security.tfstate"
  }
}

data "terraform_remote_state" "postgres" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.state_region
    key    = "${var.state_key_prefix}/${var.env}/60-postgres.tfstate"
  }
}

data "terraform_remote_state" "rke2" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.state_region
    key    = "${var.state_key_prefix}/${var.env}/50-rke2.tfstate"
  }
}

# ------------------------------------------------------------------------------
# Locals
# ------------------------------------------------------------------------------

locals {
  vpc_id   = data.terraform_remote_state.network.outputs.vpc_id
  vpc_cidr = data.terraform_remote_state.network.outputs.vpc_cidr

  # Common subnet tier (DB/공통 서비스용)
  common_subnet_ids = try(
    data.terraform_remote_state.network.outputs.subnet_ids_by_tier["common"],
    data.terraform_remote_state.network.outputs.subnet_ids_by_tier["db"],
    []
  )

  # PostgreSQL 연결 정보
  postgres_private_ip = try(data.terraform_remote_state.postgres.outputs.private_ip, "")
  postgres_password   = try(data.terraform_remote_state.postgres.outputs.db_password, "")

  # K8s 노드 SG (OIDC 토큰 검증을 위한 접근 허용)
  rke2_nodes_sg_id = try(data.terraform_remote_state.rke2.outputs.nodes_security_group_id, "")

  keycloak_hostname = "keycloak.${var.env}.${var.base_domain}"
}

# ------------------------------------------------------------------------------
# Keycloak EC2 Module
# ------------------------------------------------------------------------------

module "keycloak" {
  source = "../../../modules/keycloak-ec2"

  name    = local.name
  env     = var.env
  project = var.project
  region  = var.region

  vpc_id    = local.vpc_id
  subnet_id = local.common_subnet_ids[0]

  allowed_cidr_blocks = [local.vpc_cidr]
  allowed_sg_ids      = compact([local.rke2_nodes_sg_id])

  # Keycloak
  keycloak_version        = var.keycloak_version
  keycloak_admin_password = var.keycloak_admin_password
  keycloak_hostname       = local.keycloak_hostname

  # PostgreSQL (60-postgres)
  db_host     = local.postgres_private_ip
  db_port     = 5432
  db_name     = "keycloak"
  db_username = "keycloak"
  db_password = local.postgres_password

  # Instance
  instance_type       = var.instance_type
  root_volume_size_gb = 30

  # Golden Image
  state_bucket     = var.state_bucket
  state_region     = var.state_region
  state_key_prefix = var.state_key_prefix
  ami_id           = var.ami_id

  tags = local.common_tags
}

# ------------------------------------------------------------------------------
# Private DNS Record
# ------------------------------------------------------------------------------

data "aws_route53_zone" "private" {
  count        = var.base_domain != "" ? 1 : 0
  name         = var.base_domain
  private_zone = true
  vpc_id       = local.vpc_id
}

resource "aws_route53_record" "keycloak" {
  count   = var.base_domain != "" ? 1 : 0
  zone_id = data.aws_route53_zone.private[0].zone_id
  name    = local.keycloak_hostname
  type    = "A"
  ttl     = 300
  records = [module.keycloak.private_ip]

  allow_overwrite = true
}

# ==============================================================================
# Phase 3: AWS IAM OIDC Provider (Keycloak → AWS STS)
#
# Keycloak Realm의 OIDC Discovery를 AWS IAM에 등록하여
# Pod별 IRSA (IAM Roles for Service Accounts) 분리를 실현
#
# Usage: enable_oidc_federation = true (Phase 3 활성화 시)
# ==============================================================================

variable "enable_oidc_federation" {
  description = "Phase 3: Keycloak OIDC → AWS IAM Federation 활성화"
  type        = bool
  default     = false
}

# TLS Certificate Thumbprint (OIDC Provider 등록에 필요)
data "tls_certificate" "keycloak" {
  count = var.enable_oidc_federation ? 1 : 0
  url   = "https://${local.keycloak_hostname}/realms/platform"
}

resource "aws_iam_openid_connect_provider" "keycloak" {
  count = var.enable_oidc_federation ? 1 : 0

  url = "https://${local.keycloak_hostname}/realms/platform"

  client_id_list = [
    "sts.amazonaws.com",
    "albc",
    "argocd"
  ]

  thumbprint_list = [
    data.tls_certificate.keycloak[0].certificates[0].sha1_fingerprint
  ]

  tags = merge(local.common_tags, {
    Name = "${local.name}-oidc-provider"
  })
}

# ALBC IRSA Role (Phase 3: Node Role에서 분리)
resource "aws_iam_role" "albc_irsa" {
  count = var.enable_oidc_federation ? 1 : 0
  name  = "${var.project}-${var.env}-albc-irsa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.keycloak[0].arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.keycloak_hostname}/realms/platform:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.env}-albc-irsa-role"
  })
}

# Outputs
output "oidc_provider_arn" {
  description = "Keycloak OIDC Provider ARN (AWS IAM)"
  value       = var.enable_oidc_federation ? aws_iam_openid_connect_provider.keycloak[0].arn : null
}

output "albc_irsa_role_arn" {
  description = "ALBC IRSA Role ARN (Phase 3)"
  value       = var.enable_oidc_federation ? aws_iam_role.albc_irsa[0].arn : null
}
