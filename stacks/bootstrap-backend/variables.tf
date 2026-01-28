variable "state_region" {
  type        = string
  description = "AWS region for the tfstate bucket."
  default     = "ap-northeast-2"
}

variable "state_bucket" {
  type        = string
  description = "S3 bucket name for Terraform state."
}

variable "tags" {
  type        = map(string)
  description = "Common tags."
  default     = { ManagedBy = "terraform" }
}
