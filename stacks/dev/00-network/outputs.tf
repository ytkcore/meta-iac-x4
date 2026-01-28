output "vpc_id" {
  value = module.vpc.vpc_id
}
output "vpc_cidr" {
  value = module.vpc.vpc_cidr
}

output "subnet_ids" {
  value = module.subnets.subnet_ids
}
output "subnet_ids_by_tier" {
  value = module.subnets.subnet_ids_by_tier
}

output "nat_gateway_id_by_az" {
  value = module.nat.nat_gateway_id_by_az
}

output "public_route_table_id" {
  value = module.routing.public_route_table_id
}
output "private_route_table_ids_by_az" {
  value = module.routing.private_route_table_ids_by_az
}
output "db_route_table_ids_by_az" {
  value = module.routing.db_route_table_ids_by_az
}
output "all_route_table_ids" {
  value = module.routing.all_route_table_ids
}

output "gateway_vpc_endpoint_ids" {
  value = { for k, v in aws_vpc_endpoint.gateway : k => v.id }
}
