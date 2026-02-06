# =============================================================================
# 80-access-gateway Stack - Outputs
# =============================================================================

output "access_solution" {
  description = "Current access control solution"
  value       = var.access_solution
}

output "collected_services" {
  description = "All collected services for access gateway"
  value = {
    ec2_count = length([for s in local.ec2_services : s if s != null])
    k8s_count = length(local.k8s_services)
    total     = length(local.all_services)
    services  = [for s in local.all_services : s.name]
  }
}

output "teleport_registered_apps" {
  description = "Apps registered in Teleport"
  value       = var.access_solution == "teleport" ? module.teleport_apps[0].registered_apps : []
}

output "service_endpoint" {
  description = "Service endpoint (null for infrastructure stacks)"
  value       = null
}
