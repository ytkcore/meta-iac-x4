variable "name" {
  description = "Resource name prefix"
  type        = string
}

variable "region" {
  description = "AWS Region"
  type        = string
}

variable "tags" {
  description = "Tag map"
  type        = map(string)
  default     = {}
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block for internal connectivity"
  type        = string
}

variable "alb_security_group_id" {
  description = "Security Group ID of the Public ALB"
  type        = string
}

variable "listener_arn" {
  description = "ARN of the ALB Listener"
  type        = string
}

variable "domain_name" {
  description = "Domain name for routing rules (e.g. teleport.unifiedmeta.net)"
  type        = string
}

variable "cluster_name" {
  description = "Teleport Cluster Name (Public Hostname)"
  type        = string
}

variable "email" {
  description = "Email for Let's Encrypt (Not used in this setup but kept for compatibility)"
  type        = string
  default     = "admin@example.com"
}

variable "teleport_version" {
  description = "Teleport Version to install"
  type        = string
  default     = "18.6.6"
}

variable "base_domain" {
  description = "Base domain for application URLs (e.g. unifiedmeta.net)"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
}
