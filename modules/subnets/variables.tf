variable "name" {
  type = string
}
variable "vpc_id" {
  type = string
}

variable "subnets" {
  description = "Stable-keyed subnet map (e.g., public-a, k8s-cp-a, db-a)."
  type = map(object({
    cidr   = string
    az     = string
    tier   = string
    public = optional(bool, false)
    tags   = optional(map(string), {})
  }))
}

variable "tags" {
  type    = map(string)
  default = {}
}
