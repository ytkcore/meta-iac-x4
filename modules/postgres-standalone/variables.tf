variable "name" {
  type        = string
  description = "Workload name (e.g. postgres)."
}

variable "project" {
  type        = string
  description = "Project name."
}

variable "env" {
  type        = string
  description = "Environment name."
}

variable "vpc_id" {
  type        = string
  description = "VPC id."
}

variable "subnet_id" {
  type        = string
  description = "Subnet id (private recommended)."
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type."
  default     = "t3.large"
}

variable "root_volume_size_gb" {
  type        = number
  description = "Root volume size (GiB)."
  default     = 50
}

variable "allowed_sg_ids" {
  type        = list(string)
  description = "Source security group ids allowed to access Postgres (5432)."
  default     = []
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "Source CIDR blocks allowed to access Postgres (5432)."
  default     = []
}

variable "postgres_image_tag" {
  type        = string
  description = "Docker image tag for postgres (e.g. 18.1)."
  default     = "18.1"
}

variable "db_name" {
  type        = string
  description = "PostgreSQL database name."
  default     = "app"
}

variable "db_username" {
  type        = string
  description = "PostgreSQL username."
  default     = "app"
}

variable "db_password" {
  type        = string
  description = "PostgreSQL password."
  sensitive   = true
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to resources."
  default     = {}
}

variable "harbor_registry_hostport" {
  description = "Harbor registry host:port (예: harbor.internal:80)"
  type        = string
}

variable "harbor_scheme" {
  description = "Harbor scheme http/https"
  type        = string
  default     = "http"
}

variable "harbor_project" {
  description = "Harbor project (proxy cache)"
  type        = string
  default     = "dockerhub-proxy"
}

variable "harbor_insecure" {
  description = "true면 docker insecure-registries에 Harbor를 등록 (HTTP 또는 self-signed TLS)"
  type        = bool
  default     = true
}

variable "ami_id" {
  description = "AMI override (outbound=0 subnet 권장: ECS optimized AMI)"
  type        = string
  default     = null
}
