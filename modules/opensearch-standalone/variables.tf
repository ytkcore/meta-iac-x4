variable "name" {
  type        = string
  description = "Workload name (e.g., opensearch)"
}

variable "env" {
  type        = string
  description = "Environment (e.g., dev, prod)"
}

variable "project" {
  type        = string
  description = "Project name"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block"
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID to launch the instance in"
}

variable "instance_type" {
  type        = string
  default     = "r6i.large"
  description = "EC2 instance type (memory-optimized recommended)"
}

variable "root_volume_size_gb" {
  type        = number
  default     = 100
  description = "Root volume size in GiB"
}

variable "opensearch_image_tag" {
  type        = string
  default     = "2.18.0"
  description = "OpenSearch Docker image tag"
}

variable "dashboards_image_tag" {
  type        = string
  default     = "2.18.0"
  description = "OpenSearch Dashboards Docker image tag"
}

variable "admin_password" {
  type        = string
  sensitive   = true
  description = "OpenSearch admin password (min 8 chars, must include uppercase, lowercase, number, special char)"
}

variable "allowed_sg_ids" {
  type        = list(string)
  default     = []
  description = "List of security group IDs allowed to access OpenSearch"
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "List of CIDR blocks allowed to access OpenSearch"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags"
}

# Golden Image Configuration
variable "ami_id" {
  type        = string
  default     = null
  description = "Optional AMI ID override"
}

variable "state_bucket" {
  type        = string
  description = "Remote state bucket for Golden Image lookup"
}

variable "state_region" {
  type        = string
  description = "Remote state region"
}

variable "state_key_prefix" {
  type        = string
  description = "Remote state key prefix"
}

variable "allow_ami_fallback" {
  type        = bool
  default     = false
  description = "Allow fallback to SSM parameter if Golden Image not found"
}

# Harbor Configuration
variable "harbor_registry_hostport" {
  type        = string
  description = "Harbor registry host:port"
}

variable "harbor_scheme" {
  type        = string
  default     = "https"
  description = "Harbor scheme (http/https)"
}

variable "harbor_project" {
  type        = string
  default     = "dockerhub-proxy"
  description = "Harbor project name"
}

variable "harbor_insecure" {
  type        = bool
  default     = false
  description = "Use insecure registry"
}
