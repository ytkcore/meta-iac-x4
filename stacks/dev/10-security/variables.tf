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
variable "name" {
  type    = string
  default = null
}
variable "tags" {
  type    = map(string)
  default = {}
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

variable "admin_cidrs" {
  type    = list(string)
  default = []
}
variable "lb_ingress_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}
variable "lb_ports" {
  type    = list(number)
  default = [80, 443]
}

variable "lb_to_worker_tcp_ports" {
  type    = list(number)
  default = [80, 443]
}

variable "enable_nodeport_from_lb" {
  type    = bool
  default = true
}
variable "nodeport_from" {
  type    = number
  default = 30000
}
variable "nodeport_to" {
  type    = number
  default = 32767
}

variable "db_ports" {
  type    = list(number)
  default = [5432]
}
variable "allow_db_from_bastion" {
  type    = bool
  default = false
}

variable "azs" {
  type        = list(string)
  description = "Multi-AZ 사용 목록 (예: [\"ap-northeast-2a\",\"ap-northeast-2c\"]). env.tfvars에서 공통으로 주입됩니다."
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

