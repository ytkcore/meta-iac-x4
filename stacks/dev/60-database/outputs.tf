output "postgres_instance_id" {
  value = module.postgres.instance_id
}

output "postgres_private_ip" {
  value = module.postgres.private_ip
}

output "neo4j_instance_id" {
  value = module.neo4j.instance_id
}

output "neo4j_private_ip" {
  value = module.neo4j.private_ip
}
