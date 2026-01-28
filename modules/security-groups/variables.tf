variable "name" {
  type = string
}
variable "vpc_id" {
  type = string
}
variable "vpc_cidr" {
  type = string
}
variable "tags" {
  type    = map(string)
  default = {}
}

variable "admin_cidrs" {
  description = "Admin/VPN CIDRs allowed to access management endpoints (e.g., K8s API, internal admin services)."
  type        = list(string)
  default     = []
}
variable "lb_ingress_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}
variable "lb_ports" {
  type    = list(number)
  default = [80, 443]
}

# instance target: allow selected ports from LB SG to workers
variable "lb_to_worker_tcp_ports" {
  type    = list(number)
  default = [80, 443]
}

# optional NodePort range from LB to workers
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
