output "private_ip" {
  description = "Keycloak EC2 Private IP"
  value       = module.keycloak.private_ip
}

output "instance_id" {
  description = "Keycloak EC2 Instance ID"
  value       = module.keycloak.instance_id
}

output "security_group_id" {
  description = "Keycloak Security Group ID"
  value       = module.keycloak.security_group_id
}

output "keycloak_hostname" {
  description = "Keycloak 호스트네임"
  value       = local.keycloak_hostname
}

output "keycloak_internal_url" {
  description = "Keycloak 내부 URL"
  value       = module.keycloak.keycloak_internal_url
}

output "oidc_issuer_url" {
  description = "Keycloak OIDC Issuer URL (platform realm)"
  value       = module.keycloak.oidc_issuer_url
}

output "oidc_discovery_url" {
  description = "Keycloak OIDC Discovery URL"
  value       = module.keycloak.oidc_discovery_url
}
