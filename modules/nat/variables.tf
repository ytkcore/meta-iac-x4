variable "name" {
  type = string
}

variable "public_subnet_id_by_az" {
  description = "AZ -> public subnet id. Empty map = no NAT."
  type        = map(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}
