# ==============================================================================
# Keycloak EC2 Module — Variables
#
# Keycloak Identity Provider (SSO + Workload OIDC)
# - Docker Compose 기반 (Keycloak + 외부 PostgreSQL 연동)
# - Golden Image 기반 EC2
# ==============================================================================

variable "name" {
  description = "리소스 이름 (예: dev-meta-keycloak)"
  type        = string
}

variable "env" {
  description = "환경 (dev/staging/prod)"
  type        = string
}

variable "project" {
  description = "프로젝트/조직 식별자"
  type        = string
}

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-2"
}

# ------------------------------------------------------------------------------
# Network
# ------------------------------------------------------------------------------

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Keycloak EC2를 배포할 Private Subnet ID"
  type        = string
}

variable "allowed_cidr_blocks" {
  description = "Keycloak에 접근 가능한 CIDR 블록 (VPC CIDR)"
  type        = list(string)
  default     = []
}

variable "allowed_sg_ids" {
  description = "Keycloak에 접근 가능한 Security Group ID 목록 (K8s 노드 등)"
  type        = list(string)
  default     = []
}

# ------------------------------------------------------------------------------
# Keycloak Configuration
# ------------------------------------------------------------------------------

variable "keycloak_version" {
  description = "Keycloak Docker 이미지 버전"
  type        = string
  default     = "25.0"
}

variable "keycloak_admin_user" {
  description = "Keycloak 초기 관리자 계정"
  type        = string
  default     = "admin"
}

variable "keycloak_admin_password" {
  description = "Keycloak 초기 관리자 비밀번호"
  type        = string
  sensitive   = true
}

variable "keycloak_hostname" {
  description = "Keycloak 외부 호스트네임 (예: keycloak.dev.unifiedmeta.net)"
  type        = string
}

# ------------------------------------------------------------------------------
# PostgreSQL Connection (external DB)
# ------------------------------------------------------------------------------

variable "db_host" {
  description = "PostgreSQL 호스트 (예: postgres.dev.unifiedmeta.net)"
  type        = string
}

variable "db_port" {
  description = "PostgreSQL 포트"
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "Keycloak 전용 DB 이름"
  type        = string
  default     = "keycloak"
}

variable "db_username" {
  description = "PostgreSQL 사용자명"
  type        = string
  default     = "keycloak"
}

variable "db_password" {
  description = "PostgreSQL 비밀번호"
  type        = string
  sensitive   = true
}

# ------------------------------------------------------------------------------
# EC2 Instance
# ------------------------------------------------------------------------------

variable "instance_type" {
  description = "EC2 인스턴스 타입"
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size_gb" {
  description = "Root EBS 크기(GB)"
  type        = number
  default     = 30
}

# Golden Image
variable "state_bucket" {
  description = "Terraform state S3 bucket (Golden Image 조회용)"
  type        = string
  default     = null
}

variable "state_region" {
  description = "Terraform state region"
  type        = string
  default     = null
}

variable "state_key_prefix" {
  description = "Terraform state key prefix"
  type        = string
  default     = null
}

variable "ami_id" {
  description = "AMI ID Override (Golden Image 대신 직접 지정)"
  type        = string
  default     = null
}

variable "allow_ami_fallback" {
  description = "Golden Image 없을 시 기본 AMI 허용 여부"
  type        = bool
  default     = false
}

# Harbor
variable "harbor_registry_hostport" {
  description = "Harbor registry host:port (Docker 이미지 pull용)"
  type        = string
  default     = null
}

variable "harbor_scheme" {
  description = "Harbor 프로토콜 (http/https)"
  type        = string
  default     = "http"
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
