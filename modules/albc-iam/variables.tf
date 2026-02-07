# ==============================================================================
# AWS Load Balancer Controller — IAM Policy
#
# Description:
#   Provides the IAM permissions required for the AWS Load Balancer Controller
#   to manage ALBs and NLBs on behalf of Kubernetes.
#
# Design Decision:
#   Phase 1: Attached to Node IAM Role (all nodes share permissions)
#   Phase 3: Migrated to dedicated IRSA Role (Keycloak OIDC → STS)
# ==============================================================================

variable "env" {
  description = "환경 (dev/staging/prod)"
  type        = string
}

variable "project" {
  description = "프로젝트/조직 식별자"
  type        = string
}

variable "cluster_name" {
  description = "RKE2 클러스터 이름"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID (ALBC가 Subnet/SG 조회에 필요)"
  type        = string
}

variable "node_iam_role_name" {
  description = "Node IAM Role 이름 (Phase 1: 이 Role에 ALBC 정책 부착)"
  type        = string
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
