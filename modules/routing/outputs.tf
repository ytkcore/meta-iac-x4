output "public_route_table_id" {
  value = aws_route_table.public.id
}

output "private_route_table_ids_by_az" {
  value = { for az, rt in aws_route_table.private : az => rt.id }
}

output "db_route_table_ids_by_az" {
  value = { for az, rt in aws_route_table.db : az => rt.id }
}

output "all_route_table_ids" {
  value = concat(
    [aws_route_table.public.id],
    [for _, rt in aws_route_table.private : rt.id],
    [for _, rt in aws_route_table.db : rt.id]
  )
}
