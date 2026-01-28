variable "name" {
  type = string
}
variable "subnet_ids" {
  type = list(string)
}
variable "tags" {
  type    = map(string)
  default = {}
}
