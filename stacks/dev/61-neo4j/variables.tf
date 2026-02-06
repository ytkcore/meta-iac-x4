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
  description = "EC2 instance type for Neo4j."
}

variable "root_volume_gb" {
  type        = number
  default     = 50
  description = "Root volume size (GiB) for Neo4j."
}

variable "neo4j_image_tag" {
  type        = string
  default     = "5.26.19"
  description = "Docker image tag for neo4j (e.g., 5.26.19)."
}

variable "neo4j_password" {
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
