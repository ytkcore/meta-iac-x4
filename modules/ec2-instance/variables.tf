variable "name" {
  description = "Resource name (workload name)"
  type        = string
}

variable "env" {
  description = "Environment name"
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

variable "instance_type" {
  description = "EC2 Instance Type"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID where instance will be launched"
  type        = string
}

variable "vpc_security_group_ids" {
  description = "List of Security Group IDs"
  type        = list(string)
}

variable "key_name" {
  description = "SSH Key Pair Name (Optional)"
  type        = string
  default     = null
}

variable "user_data" {
  description = "User Data Script (Optional)"
  type        = string
  default     = null
}

variable "user_data_base64" {
  description = "Base64 Encoded User Data (Optional, overrides user_data)"
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 30
}

variable "ami_id" {
  description = "AMI ID Override (Optional, bypasses Golden Image lookup if provided)"
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Golden Image Configuration
# -----------------------------------------------------------------------------
variable "state_bucket" {
  description = "Terraform state S3 bucket (required for Golden Image lookup)"
  type        = string
  default     = null
}

variable "state_region" {
  description = "Terraform state region (required for Golden Image lookup)"
  type        = string
  default     = null
}

variable "state_key_prefix" {
  description = "Terraform state key prefix (required for Golden Image lookup)"
  type        = string
  default     = null
}

variable "allow_ami_fallback" {
  description = "Allow fallback to default AMI if Golden Image not found (default: false = error on missing Golden Image)"
  type        = bool
  default     = false
}

