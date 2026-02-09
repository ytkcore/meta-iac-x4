output "instance_id" {
  description = "Neo4j EC2 instance ID"
  value       = module.neo4j.instance_id
}

output "private_ip" {
  description = "Neo4j private IP address"
  value       = module.neo4j.private_ip
}

output "fqdn" {
  description = "Neo4j FQDN (if Route53 record created)"
  value       = length(aws_route53_record.neo4j) > 0 ? aws_route53_record.neo4j[0].fqdn : null
}

output "neo4j_password" {
  description = "Neo4j database password"
  value       = local.neo4j_password_effective
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Access Gateway Integration (솔루션 독립적)
# -----------------------------------------------------------------------------
output "service_endpoint" {
  description = "Service endpoint for access-gateway integration"
  value = length(aws_route53_record.neo4j) > 0 ? {
    name     = "neo4j"
    uri      = "http://${aws_route53_record.neo4j[0].fqdn}:7474"
    type     = "web"
    internal = true
  } : null
}
