variable "env" {
  type        = string
  description = "Environment name (e.g., dev/prod)."
}

variable "project" {
  type        = string
  description = "Project/service name."
}

variable "region" {
  type        = string
  default     = "ap-northeast-2"
  description = "AWS region."
}

variable "state_bucket" {
  type        = string
  description = "Remote state bucket name."
}

variable "state_region" {
  type        = string
  default     = "ap-northeast-2"
  description = "Remote state bucket region."
}

variable "state_key_prefix" {
  type        = string
  description = "Remote state key prefix (folder-like)."
}

variable "instance_type" {
  type        = string
  default     = "r6i.large"
  description = "EC2 instance type for OpenSearch (memory-optimized recommended)."
}

variable "root_volume_gb" {
  type        = number
  default     = 100
  description = "Root volume size (GiB) for OpenSearch."
}

variable "opensearch_image_tag" {
  type        = string
  default     = "2.18.0"
  description = "OpenSearch Docker image tag."
}

variable "dashboards_image_tag" {
  type        = string
  default     = "2.18.0"
  description = "OpenSearch Dashboards Docker image tag."
}

variable "admin_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "OpenSearch admin password. If null, Terraform will generate a random password."
}

# Golden Image Configuration
variable "ami_id" {
  type        = string
  default     = null
  description = "Optional AMI ID override (if not using Golden Image remote state)."
}

variable "base_domain" {
  type        = string
  description = "Base domain (compatible with global env.tfvars)"
  default     = null
}
