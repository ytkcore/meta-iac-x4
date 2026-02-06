output "instance_id" {
  description = "PostgreSQL EC2 instance ID"
  value       = module.postgres.instance_id
}

output "private_ip" {
  description = "PostgreSQL private IP address"
  value       = module.postgres.private_ip
}

output "fqdn" {
  description = "PostgreSQL FQDN (if Route53 record created)"
  value       = length(aws_route53_record.postgres) > 0 ? aws_route53_record.postgres[0].fqdn : null
}

output "db_password" {
  description = "PostgreSQL database password"
  value       = local.postgres_password_effective
  sensitive   = true
}
