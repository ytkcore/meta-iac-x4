variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "env" {
  type = string
}

variable "project" {
  type = string
}

variable "state_bucket" {
  type    = string
  default = "iac-dev-apne2-tfstate"
}

variable "state_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "state_key_prefix" {
  type    = string
  default = "iac"
}

variable "base_domain" {
  type = string
}

variable "teleport_version" {
  type    = string
  default = "18.6.6"
}

variable "ami_id" {
  type = string
  # Amazon Linux 2023 or similar (Golden Image ID)
  # Default to null to trigger Golden Image lookup
  default = null
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "email" {
  type    = string
  default = "admin@unifiedmeta.net" # Dummy default, should be overridden
}

variable "enable_ha" {
  description = "Enable HA mode (2 instances in different AZs)"
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}


# Dummy variables for env.tfvars compatibility
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

# Variables from other stacks (if needed)
variable "vpc_cidr_block" {
  type    = string
  default = ""
}

variable "interface_subnet_tiers" {
  type    = any
  default = []
}
