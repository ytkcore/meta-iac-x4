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
  description = "AMI ID (Amazon Linux 2 or Ubuntu)"
  type        = string
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
