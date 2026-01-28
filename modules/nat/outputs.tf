output "nat_gateway_id_by_az" {
  value = { for az, ngw in aws_nat_gateway.this : az => ngw.id }
}

output "eip_allocation_id_by_az" {
  value = { for az, e in aws_eip.nat : az => e.id }
}
