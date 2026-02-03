output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "subnet_ids" {
  description = "Map of all subnet IDs keyed by name"
  value       = { for k, v in aws_subnet.this : k => v.id }
}

output "subnet_ids_by_tier" {
  description = "Map of subnet IDs grouped by tier"
  value = {
    for tier in distinct([for v in local.final_subnets : v.tier]) :
    tier => [
      for k, v in local.final_subnets : aws_subnet.this[k].id if v.tier == tier
    ]
  }
}

output "subnet_cidrs_by_tier" {
  description = "Map of subnet CIDR blocks grouped by tier"
  value = {
    for tier in distinct([for v in local.final_subnets : v.tier]) :
    tier => [
      for k, v in local.final_subnets : aws_subnet.this[k].cidr_block if v.tier == tier
    ]
  }
}

output "nat_gateway_id_by_az" {
  description = "Map of NAT Gateway IDs keyed by AZ"
  value       = { for k, v in aws_nat_gateway.this : k => v.id }
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_route_table_ids_by_az" {
  description = "Map of private route table IDs keyed by AZ"
  value       = { for k, v in aws_route_table.private : k => v.id }
}

output "db_route_table_ids_by_az" {
  description = "Map of DB route table IDs keyed by AZ"
  value       = { for k, v in aws_route_table.db : k => v.id }
}

output "all_route_table_ids" {
  description = "List of all route table IDs (standard and private/db)"
  value = concat(
    [aws_route_table.public.id],
    values(aws_route_table.private)[*].id,
    values(aws_route_table.db)[*].id
  )
}

output "gateway_vpc_endpoint_ids" {
  description = "Map of Gateway VPC Endpoint IDs keyed by service name"
  value       = { for k, v in aws_vpc_endpoint.gateway : k => v.id }
}

output "route53_zone_id" {
  description = "The ID of the created Route53 Private Hosted Zone."
  value       = try(aws_route53_zone.private[0].zone_id, "")
}
