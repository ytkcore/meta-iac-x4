# ==============================================================================
# 25-keycloak Stack
#
# Description:
#   Keycloak Identity Provider — OIDC Federation
#   - Keycloak 자체는 K8s(RKE2) Helm Chart로 배포 (ArgoCD 관리)
#   - 이 스택은 AWS IAM OIDC Provider + IRSA Role만 관리
#
# Dependencies:
#   - 00-network (VPC)
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

  keycloak_hostname = "keycloak.${var.env}.${var.base_domain}"
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
output "keycloak_hostname" {
  description = "Keycloak 호스트네임"
  value       = local.keycloak_hostname
}

output "oidc_provider_arn" {
  description = "Keycloak OIDC Provider ARN (AWS IAM)"
  value       = var.enable_oidc_federation ? aws_iam_openid_connect_provider.keycloak[0].arn : null
}

output "albc_irsa_role_arn" {
  description = "ALBC IRSA Role ARN (Phase 3)"
  value       = var.enable_oidc_federation ? aws_iam_role.albc_irsa[0].arn : null
}
