variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "env" {
  type = string
}

variable "project" {
  type = string
}

variable "state_bucket" {
  type    = string
  default = "iac-dev-apne2-tfstate"
}

variable "state_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "state_key_prefix" {
  type    = string
  default = "iac"
}

variable "rate_limit" {
  description = "WAF Rate Limit (requests per 5 minutes)"
  type        = number
  default     = 2000
}

variable "tags" {
  type    = map(string)
  default = {}
}
