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
  default     = "t3.large"
  description = "EC2 instance type for PostgreSQL."
}

variable "root_volume_gb" {
  type        = number
  default     = 50
  description = "Root volume size (GiB) for PostgreSQL."
}

variable "postgres_image_tag" {
  type        = string
  default     = "18.1"
  description = "Docker image tag for postgres (e.g., 18.1)."
}

variable "db_name" {
  type        = string
  default     = "app"
  description = "Default database name."
}

variable "db_username" {
  type        = string
  default     = "app"
  description = "Default database username."
}

variable "postgres_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "If null, Terraform will generate a random password."
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
