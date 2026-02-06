variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-2"
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "base_domain" {
  description = "Base domain name"
  type        = string
}

variable "state_bucket" {
  description = "Terraform state S3 bucket"
  type        = string
}

variable "state_key_prefix" {
  description = "Terraform state key prefix"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR (Unused but passed by env.tfvars)"
  type        = string
  default     = ""
}

variable "target_bucket_name" {
  description = "Harbor bucket (Unused)"
  type        = string
  default     = ""
}

variable "longhorn_backup_bucket" {
  description = "Longhorn bucket (Unused)"
  type        = string
  default     = ""
}

variable "region" {
  description = "Legacy region var"
  type        = string
  default     = ""
}

variable "azs" {
  description = "Availability Zones (Unused)"
  type        = list(string)
  default     = []
}

variable "enable_interface_endpoints" {
  type    = bool
  default = false
}

variable "interface_services" {
  type    = list(string)
  default = []
}

variable "interface_subnet_tiers" {
  type    = list(string)
  default = []
}

variable "enable_gitops_apps" {
  type    = bool
  default = false
}

variable "gitops_apps_path" {
  type    = string
  default = ""
}

variable "gitops_repo_url" {
  type    = string
  default = ""
}

variable "gitops_ssh_key_path" {
  type    = string
  default = ""
}
