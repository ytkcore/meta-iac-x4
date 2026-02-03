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
output "subnet_cidrs_by_tier" {
  value = module.network.subnet_cidrs_by_tier
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

output "route53_zone_id" {
  value       = module.network.route53_zone_id
  description = "The ID of the created Route53 Private Hosted Zone."
}

output "base_domain" {
  value       = var.base_domain
  description = "The base domain used for the environment."
}
