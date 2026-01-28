variable "name" {
  description = "Resource name prefix"
  type        = string
}

variable "env" {
  description = "Environment name"
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

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 30
}
