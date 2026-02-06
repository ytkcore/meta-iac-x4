output "postgres_private_ip" {
  value = module.postgres.private_ip
}

output "postgres_port" {
  value = 5432
}

output "postgres_username" {
  value = var.postgres_username
}

output "postgres_db_name" {
  value = var.postgres_db_name
}

output "neo4j_private_ip" {
  value = module.neo4j.private_ip
}

output "neo4j_bolt_uri" {
  value = module.neo4j.bolt_uri
}

output "neo4j_http_uri" {
  value = module.neo4j.http_uri
}
