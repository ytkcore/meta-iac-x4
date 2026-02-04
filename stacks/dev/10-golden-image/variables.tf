# =============================================================================
# 10-golden-image Variables
# =============================================================================

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-2"
}

variable "env" {
  description = "Environment (dev/prod)"
  type        = string
}

variable "project" {
  description = "Project identifier"
  type        = string
}

# -----------------------------------------------------------------------------
# Remote State (env.tfvars 호환)
# -----------------------------------------------------------------------------
variable "state_bucket" {
  description = "Terraform remote state S3 bucket"
  type        = string
  default     = ""
}

variable "state_region" {
  description = "Terraform remote state S3 region"
  type        = string
  default     = "ap-northeast-2"
}

variable "state_key_prefix" {
  description = "Terraform remote state key prefix"
  type        = string
  default     = "iac"
}

# -----------------------------------------------------------------------------
# SSH Configuration
# -----------------------------------------------------------------------------
variable "ssh_port" {
  description = "SSH daemon port (22: standard, 22022: hardened). Set via 'make init'"
  type        = number
  default     = 22
  
  validation {
    condition     = contains([22, 2222, 22022], var.ssh_port)
    error_message = "SSH port must be 22, 2222, or 22022"
  }
}

# -----------------------------------------------------------------------------
# Component On/Off Defaults
# -----------------------------------------------------------------------------
variable "docker_enabled" {
  description = "Docker default enabled state in Golden Image"
  type        = bool
  default     = true
}

variable "cloudwatch_agent_enabled" {
  description = "CloudWatch Agent default enabled state"
  type        = bool
  default     = false  # 비용 최적화: 기본 비활성화
}

variable "teleport_agent_enabled" {
  description = "Teleport Agent default enabled state"
  type        = bool
  default     = false  # 스택별 user-data에서 제어
}

# -----------------------------------------------------------------------------
# Dummy Variables (env.tfvars 호환)
# -----------------------------------------------------------------------------
variable "base_domain" {
  type    = string
  default = ""
}

variable "azs" {
  type    = list(string)
  default = []
}

variable "vpc_cidr" {
  type    = string
  default = ""
}

variable "target_bucket_name" {
  type    = string
  default = ""
}

variable "longhorn_backup_bucket" {
  type    = string
  default = ""
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
