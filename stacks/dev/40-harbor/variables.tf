# =============================================================================
# Variables - Harbor Stack
# =============================================================================

# -----------------------------------------------------------------------------
# Basic
# -----------------------------------------------------------------------------
variable "region" {
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

# name 제거 (locals 자동 생성)
# tags 제거 (locals 자동 생성/default)

# -----------------------------------------------------------------------------
# Remote State
# -----------------------------------------------------------------------------
variable "state_bucket" {
  description = "Terraform remote state S3 bucket"
  type        = string
  default     = null
}

variable "state_region" {
  description = "Terraform remote state region"
  type        = string
  default     = null
}

variable "state_key_prefix" {
  description = "Terraform remote state key prefix"
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------
variable "harbor_subnet_key" {
  description = "Subnet key in 00-network outputs for Harbor EC2"
  type        = string
  default     = "common-pri-c"
}

# -----------------------------------------------------------------------------
# EC2
# -----------------------------------------------------------------------------
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.large"
}

variable "key_name" {
  description = "SSH key name (optional, SSM recommended)"
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "Root EBS volume size (GB)"
  type        = number
  default     = 100
}

# -----------------------------------------------------------------------------
# Harbor App
# -----------------------------------------------------------------------------
variable "harbor_enable_tls" {
  description = "Enable TLS on Harbor (internal)"
  type        = bool
  default     = false
}

variable "admin_password" {
  description = "Harbor admin password"
  type        = string
  default     = "Harbor12345"
  sensitive   = true
}

variable "db_password" {
  description = "Harbor internal database password"
  type        = string
  default     = "root123"
  sensitive   = true
}

variable "harbor_proxy_cache_project" {
  description = "Docker Hub proxy cache project name"
  type        = string
  default     = "dockerhub-proxy"
}

variable "create_proxy_cache" {
  description = "Create Docker Hub proxy cache project"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Storage
# -----------------------------------------------------------------------------
variable "storage_type" {
  description = "Storage backend (filesystem or s3)"
  type        = string
  default     = "filesystem"
}

variable "target_bucket_name" {
  description = "S3 bucket name for Harbor storage"
  type        = string
  default     = null # Will be auto-generated if null
}

variable "create_bucket" {
  description = "Create S3 bucket"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# ALB / ACM
# -----------------------------------------------------------------------------
variable "enable_alb" {
  description = "Create ALB for Harbor"
  type        = bool
  default     = true
}

variable "alb_certificate_arn" {
  description = "ACM certificate ARN (empty = auto-discover *.base_domain)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Route53
# -----------------------------------------------------------------------------
variable "base_domain" {
  description = "Base domain (e.g., example.com)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9.-]+$", var.base_domain))
    error_message = "도메인 형식은 소문자, 숫자, 점(.), 하이픈(-)만 허용됩니다."
  }
}

variable "enable_route53_harbor_cname" {
  description = "Create Route53 CNAME for harbor.<base_domain>"
  type        = bool
  default     = true
}

variable "route53_zone_id" {
  description = "Route53 Zone ID (empty = auto-discover)"
  type        = string
  default     = ""
}

variable "dns_scope" {
  description = "DNS registration scope (public, private, or both)"
  type        = string
  default     = "private"

  validation {
    condition     = contains(["public", "private", "both"], var.dns_scope)
    error_message = "Must be: public, private, or both"
  }
}

# -----------------------------------------------------------------------------
# Helm Chart Seeding
# -----------------------------------------------------------------------------
variable "helm_seeding_mode" {
  description = "Helm seeding mode: disabled, local-exec, user-data"
  type        = string
  default     = "user-data"

  validation {
    condition     = contains(["disabled", "local-exec", "user-data"], var.helm_seeding_mode)
    error_message = "Must be: disabled, local-exec, or user-data"
  }
}

variable "argocd_chart_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "5.55.0"
}

variable "certmanager_chart_version" {
  description = "cert-manager Helm chart version"
  type        = string
  default     = "v1.14.5"
}

variable "rancher_chart_version" {
  description = "Rancher Helm chart version"
  type        = string
  default     = "2.10.3"
}

# -----------------------------------------------------------------------------
# Image Seeding
# -----------------------------------------------------------------------------
variable "seed_images" {
  description = "Pre-pull and push seed images"
  type        = bool
  default     = false
}

variable "seed_postgres_tag" {
  description = "PostgreSQL image tag to seed"
  type        = string
  default     = ""
}

variable "seed_neo4j_tag" {
  description = "Neo4j image tag to seed"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Golden Image Configuration
# -----------------------------------------------------------------------------
variable "ami_id" {
  description = "Optional AMI ID override (if not using Golden Image)"
  type        = string
  default     = null
}

variable "allow_ami_fallback" {
  description = "Allow fallback to default AMI if Golden Image not found (true=fallback, false=error)"
  type        = bool
  default     = false
}

