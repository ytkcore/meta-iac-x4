variable "name" {
  description = "Resource name prefix"
  type        = string
}

variable "region" {
  description = "AWS Region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs to deploy Teleport Instances (for HA, provide 2 subnets in different AZs)"
  type        = list(string)
}

variable "enable_ha" {
  description = "Enable HA mode (2 instances across AZs)"
  type        = bool
  default     = false
}

variable "ami_id" {
  description = "AMI ID override (Optional, bypasses Golden Image lookup if provided)"
  type        = string
  default     = null
}

variable "instance_type" {
  description = "Instance type"
  type        = string
  default     = "t3.medium"
}

variable "alb_security_group_ids" {
  description = "Security Group IDs of the ALB (to allow access to Teleport)"
  type        = list(string)
  default     = []
}

variable "vpc_cidr" {
  description = "VPC CIDR block for internal connectivity (Reverse Tunnel, Agent)"
  type        = string
}

variable "listener_arn" {
  description = "ALB HTTPS Listener ARN (null = no ALB routing)"
  type        = string
  default     = null
}

variable "domain_name" {
  description = "Domain for ALB routing rules (e.g. teleport.unifiedmeta.net)"
  type        = string
  default     = null
}

variable "base_domain" {
  description = "Base domain for application URLs (e.g. unifiedmeta.net)"
  type        = string
}

variable "cluster_name" {
  description = "Teleport Cluster Name (e.g., teleport.example.com)"
  type        = string
}

variable "email" {
  description = "Email for Let's Encrypt (if used) or Admin"
  type        = string
}

variable "teleport_version" {
  description = "Teleport version to install"
  type        = string
  default     = "14.3.3" # 최신 안정 버전
}

variable "tags" {
  description = "Tags"
  type        = map(string)
  default     = {}
}

# Golden Image State Configuration
variable "env" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

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

