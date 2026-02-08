# =============================================================================
# 15-access-control Outputs
# =============================================================================

output "access_solution" {
  description = "Selected access control solution"
  value       = var.access_solution
}

output "teleport_url" {
  value = var.access_solution == "teleport" ? "https://teleport.${var.base_domain}" : null
}

output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "instance_id" {
  value = var.access_solution == "teleport" ? module.teleport[0].instance_id : null
}

output "private_ip" {
  value = var.access_solution == "teleport" ? module.teleport[0].private_ip : null
}

# -----------------------------------------------------------------------------
# Access Gateway Integration
# -----------------------------------------------------------------------------
output "teleport_server" {
  description = "Teleport server information for access-gateway integration"
  value = var.access_solution == "teleport" ? {
    instance_id  = module.teleport[0].instance_id
    private_ip   = module.teleport[0].private_ip
    cluster_name = "teleport.${var.base_domain}"
    domain       = var.base_domain
  } : null
}
