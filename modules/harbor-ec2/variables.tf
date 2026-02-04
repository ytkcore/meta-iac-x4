# -----------------------------------------------------------------------------
# Harbor EC2 Module Variables - Enhanced Version
# -----------------------------------------------------------------------------

# --- Basic ---
variable "name" {
  description = "Name prefix for resources (workload name)"
  type        = string
}

variable "env" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-2"
}

# --- Network & Compute ---
variable "vpc_id" {
  description = "VPC ID where Harbor will be deployed"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type (recommend t3.large or higher)"
  type        = string
  default     = "t3.large"
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
  default     = null
}

variable "allow_ssh_cidrs" {
  description = "Optional: CIDR blocks allowed to SSH into the Harbor instance. Default is empty (SSM recommended)."
  type        = list(string)
  default     = []
}

variable "additional_ingress_sg_ids" {
  description = "Additional Security Group IDs allowed to access Harbor (e.g., K8s Client SG)"
  type        = list(string)
  default     = []
}

variable "allowed_inbound_cidrs" {
  description = "CIDR blocks allowed to access Harbor directly (default: 0.0.0.0/0)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB (Harbor needs space for images)"
  type        = number
  default     = 100
}

# --- Harbor App Config ---
variable "harbor_hostname" {
  description = "Hostname for Harbor (e.g., harbor.example.com or private IP)"
  type        = string
}

variable "harbor_version" {
  description = "Harbor version to install"
  type        = string
  default     = "2.10.0"
}

variable "enable_tls" {
  description = "Enable TLS/HTTPS"
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

# --- Storage Config ---
variable "storage_type" {
  description = "Storage backend type (filesystem or s3)"
  type        = string
  default     = "filesystem"
  validation {
    condition     = contains(["filesystem", "s3"], var.storage_type)
    error_message = "storage_type must be 'filesystem' or 's3'"
  }
}

variable "target_bucket_name" {
  description = "S3 bucket name for Harbor storage (required if storage_type is s3)"
  type        = string
  default     = ""

  validation {
    condition     = var.storage_type != "s3" || length(trimspace(var.target_bucket_name)) > 0
    error_message = "target_bucket_name must be set when storage_type is 's3'."
  }
}

variable "create_bucket" {
  description = "Whether to create S3 bucket or use existing"
  type        = bool
  default     = true
}

# --- Proxy Cache & Seeding ---
variable "proxy_cache_project" {
  description = "Name of the proxy cache project to create"
  type        = string
  default     = "dockerhub-proxy"
}

variable "create_proxy_cache" {
  description = "Whether to create Docker Hub proxy cache project"
  type        = bool
  default     = false
}

variable "seed_images" {
  description = "Whether to pre-pull and push seed images"
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
# Helm Chart Seeding (OCI Registry)
# - Harbor를 OCI 호환 Helm Chart 저장소로 사용
# - 외부 네트워크 접근이 제한된 환경에서 Bootstrap 차트 미리 캐싱
# -----------------------------------------------------------------------------
variable "seed_helm_charts" {
  description = "Whether to download and push Helm charts to Harbor OCI registry"
  type        = bool
  default     = true
}

variable "argocd_chart_version" {
  description = "ArgoCD Helm chart version to seed"
  type        = string
  default     = "5.55.0"
}

variable "certmanager_chart_version" {
  description = "cert-manager Helm chart version to seed"
  type        = string
  default     = "v1.14.5"
}

variable "rancher_chart_version" {
  description = "Rancher Helm chart version to seed"
  type        = string
  default     = "2.10.10"
}

# -----------------------------------------------------------------------------
# ALB Configuration (Optional)
# -----------------------------------------------------------------------------
variable "enable_alb" {
  description = "Enable ALB for Harbor access"
  type        = bool
  default     = false
}

variable "alb_subnet_ids" {
  description = "Subnet IDs for ALB (typically public subnets)"
  type        = list(string)
  default     = []
}

variable "alb_certificate_arn" {
  description = "ACM certificate ARN for HTTPS (optional, enables HTTPS listener)"
  type        = string
  default     = null
}

variable "alb_internal" {
  description = "Whether ALB is internal (true) or internet-facing (false)"
  type        = bool
  default     = false
}

variable "alb_ingress_cidrs" {
  description = "CIDR blocks allowed to access ALB (default: 0.0.0.0/0)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# --- AMI Configuration ---
variable "ami_id" {
  description = "AMI ID Override (Optional, defaults to ec2-instance module default)"
  type        = string
  default     = null
}

# Golden Image State Configuration
variable "state_bucket" {
  description = "Terraform state S3 bucket (for Golden Image lookup)"
  type        = string
  default     = null
}

variable "state_region" {
  description = "Terraform state region (for Golden Image lookup)"
  type        = string
  default     = null
}

variable "state_key_prefix" {
  description = "Terraform state key prefix (for Golden Image lookup)"
  type        = string
  default     = null
}

variable "allow_ami_fallback" {
  description = "Allow fallback to default AMI if Golden Image not found"
  type        = bool
  default     = false
}


