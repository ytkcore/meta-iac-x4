output "vpc_id" {
  value = module.network.vpc_id
}
output "vpc_cidr" {
  value = module.network.vpc_cidr
}

output "subnet_ids" {
  value = module.network.subnet_ids
}
output "subnet_ids_by_tier" {
  value = module.network.subnet_ids_by_tier
}

output "nat_gateway_id_by_az" {
  value = module.network.nat_gateway_id_by_az
}

output "public_route_table_id" {
  value = module.network.public_route_table_id
}
output "private_route_table_ids_by_az" {
  value = module.network.private_route_table_ids_by_az
}
output "db_route_table_ids_by_az" {
  value = module.network.db_route_table_ids_by_az
}
output "all_route_table_ids" {
  value = module.network.all_route_table_ids
}

output "gateway_vpc_endpoint_ids" {
  value = module.network.gateway_vpc_endpoint_ids
}
