variable "env" {
  type        = string
  description = "Environment name (e.g., dev/prod)."
}

variable "state_bucket" {
  type        = string
  description = "Remote state bucket name."
}

variable "state_region" {
  type        = string
  default     = "ap-northeast-2"
  description = "Remote state bucket region."
}

variable "state_key_prefix" {
  type        = string
  description = "Remote state key prefix (folder-like)."
}

variable "base_domain" {
  type        = string
  description = "Base domain (fallback if not in network state)"
  default     = null
}
