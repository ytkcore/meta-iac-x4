variable "name" {
  type = string
}
variable "cidr" {
  type = string
}
variable "enable_dns_support" {
  type    = bool
  default = true
}
variable "enable_dns_hostnames" {
  type    = bool
  default = true
}
variable "tags" {
  type    = map(string)
  default = {}
}
