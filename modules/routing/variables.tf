variable "name" {
  type = string
}
variable "vpc_id" {
  type = string
}
variable "igw_id" {
  type = string
}

variable "public_subnet_ids" {
  type    = list(string)
  default = []
}

variable "private_subnet_ids_by_az" {
  description = "AZ -> list of private subnet IDs (e.g., k8s cp+dp)"
  type        = map(list(string))
  default     = {}
}

variable "db_subnet_ids_by_az" {
  description = "AZ -> list of DB subnet IDs"
  type        = map(list(string))
  default     = {}
}

variable "enable_nat" {
  type    = bool
  default = true
}

variable "nat_gateway_id_by_az" {
  description = "AZ -> NAT gateway ID"
  type        = map(string)
  default     = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "enable_nat_for_db" {
  type        = bool
  default     = true
  description = "Whether DB route tables should have a default route to NAT (for outbound access / SSM)."
}
