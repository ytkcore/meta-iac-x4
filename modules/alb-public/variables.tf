variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

variable "certificate_arn" {
  description = "ACM Certificate ARN for HTTPS"
  type        = string
}

variable "tags" {
  description = "Tag map"
  type        = map(string)
  default     = {}
}
