variable "env" {
  description = "환경 (dev/prod)"
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

variable "longhorn_backup_bucket" {
  description = "Longhorn S3 백업 버킷 이름"
  type        = string
  default     = ""
}

variable "velero_backup_bucket" {
  description = "Velero S3 백업 버킷 이름 (Disaster Recovery)"
  type        = string
  default     = ""
}
