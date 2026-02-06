# =============================================================================
# Teleport Access Gateway Module - Outputs
# =============================================================================

output "registered_apps" {
  description = "List of registered Teleport apps"
  value = [
    for app in local.teleport_apps_config : {
      name        = app.name
      public_addr = app.public_addr
      uri         = app.uri
    }
  ]
}

output "apps_count" {
  description = "Number of registered apps"
  value       = length(local.internal_services)
}

output "apps_config_yaml" {
  description = "Teleport apps configuration in YAML format"
  value       = local.apps_yaml
  sensitive   = true
}
