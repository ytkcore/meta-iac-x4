# ==============================================================================
# 25-keycloak Stack Variables
# ==============================================================================

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

variable "state_bucket" {
  description = "Terraform remote state S3 bucket"
  type        = string
}

variable "state_region" {
  description = "Terraform remote state S3 region"
  type        = string
}

variable "state_key_prefix" {
  description = "Terraform remote state key prefix"
  type        = string
}

variable "base_domain" {
  description = "루트 도메인 (예: unifiedmeta.net)"
  type        = string
}

# ------------------------------------------------------------------------------
# Keycloak Configuration
# ------------------------------------------------------------------------------

variable "keycloak_admin_password" {
  description = "Keycloak 초기 관리자 비밀번호"
  type        = string
  sensitive   = true
  default     = "Keycloak12345"
}

variable "keycloak_version" {
  description = "Keycloak Docker 이미지 버전"
  type        = string
  default     = "25.0"
}

variable "instance_type" {
  description = "Keycloak EC2 인스턴스 타입"
  type        = string
  default     = "t3.medium"
}

variable "ami_id" {
  description = "AMI ID Override (Golden Image 대신 직접 지정)"
  type        = string
  default     = null
}

# Unused (env.tfvars 공통 변수 suppression)
variable "azs" {
  type    = any
  default = []
}
variable "vpc_cidr" {
  type    = any
  default = ""
}
variable "longhorn_backup_bucket" {
  type    = any
  default = ""
}
variable "interface_services" {
  type    = any
  default = {}
}
