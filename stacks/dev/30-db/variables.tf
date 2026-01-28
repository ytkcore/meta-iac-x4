variable "region" {
  type = string
}
variable "env" {
  type = string
}
variable "project" {
  type = string
}
variable "name" {
  type = string
}
variable "tags" {
  type = map(string)
}

variable "state_bucket" {
  type = string
}
variable "state_region" {
  type = string
}
variable "state_key_prefix" {
  type = string
}

variable "db_subnet_group_name" {
  type    = string
  default = null
}

variable "azs" {
  type        = list(string)
  description = "Multi-AZ 사용 목록 (예: [\"ap-northeast-2a\",\"ap-northeast-2c\"]). env.tfvars에서 공통으로 주입됩니다."
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

