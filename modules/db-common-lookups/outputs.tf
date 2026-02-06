# Network outputs
output "vpc_id" {
  description = "VPC ID from network stack"
  value       = local.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR from network stack"
  value       = local.vpc_cidr
}

output "db_subnet_ids" {
  description = "DB subnet IDs by AZ (a, c)"
  value       = local.db_subnet_ids
}

# Security outputs
output "allowed_sgs" {
  description = "Allowed security group IDs (k8s_client, ops_client)"
  value       = local.allowed_sgs
}

output "allowed_cidrs" {
  description = "Allowed CIDR blocks (VPC + K8s subnets)"
  value       = local.allowed_cidrs
}

# Harbor outputs
output "harbor_registry_hostport" {
  description = "Harbor registry host:port"
  value       = local.harbor_registry_hostport
}

output "harbor_scheme" {
  description = "Harbor scheme (http/https)"
  value       = local.harbor_scheme
}

output "harbor_project" {
  description = "Harbor proxy cache project name"
  value       = local.harbor_project
}

# DNS outputs
output "route53_zone_id" {
  description = "Route53 Private Hosted Zone ID"
  value       = local.route53_zone_id
}

output "base_domain" {
  description = "Base domain for DNS records"
  value       = local.base_domain
}
