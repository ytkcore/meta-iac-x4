output "subnet_ids" {
  value = { for k, s in aws_subnet.this : k => s.id }
}

output "subnet_ids_by_tier" {
  value = {
    for t in distinct([for _, v in var.subnets : v.tier]) :
    t => [for k, v in var.subnets : try(aws_subnet.this[k].id, null) if v.tier == t && try(aws_subnet.this[k].id, null) != null]
  }
}

output "subnet_ids_by_az" {
  value = {
    for az in distinct([for _, v in var.subnets : v.az]) :
    az => [for k, v in var.subnets : try(aws_subnet.this[k].id, null) if v.az == az && try(aws_subnet.this[k].id, null) != null]
  }
}
