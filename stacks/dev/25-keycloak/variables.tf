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
