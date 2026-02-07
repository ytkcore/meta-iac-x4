output "private_ip" {
  description = "Keycloak EC2 Private IP"
  value       = module.instance.private_ip
}

output "instance_id" {
  description = "Keycloak EC2 Instance ID"
  value       = module.instance.instance_id
}

output "security_group_id" {
  description = "Keycloak Security Group ID"
  value       = aws_security_group.keycloak.id
}

output "keycloak_internal_url" {
  description = "Keycloak 내부 접근 URL (VPC 내부)"
  value       = "https://${var.keycloak_hostname}:8443"
}

output "oidc_issuer_url" {
  description = "Keycloak OIDC Issuer URL (Realm 기반)"
  value       = "https://${var.keycloak_hostname}/realms/platform"
}

output "oidc_discovery_url" {
  description = "Keycloak OIDC Discovery URL"
  value       = "https://${var.keycloak_hostname}/realms/platform/.well-known/openid-configuration"
}
