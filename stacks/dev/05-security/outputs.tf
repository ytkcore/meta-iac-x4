output "bastion_sg_id" {
  value = module.security_groups.bastion_sg_id
}
output "lb_public_sg_id" {
  value = module.security_groups.lb_public_sg_id
}
output "k8s_cp_sg_id" {
  value = module.security_groups.k8s_cp_sg_id
}
output "k8s_worker_sg_id" {
  value = module.security_groups.k8s_worker_sg_id
}
output "db_sg_id" {
  value = module.security_groups.db_sg_id
}
output "vpce_sg_id" {
  value = module.security_groups.vpce_sg_id
}

output "k8s_client_sg_id" {
  description = "Logical security group id for K8s nodes (identity-only)."
  value       = module.security_groups.k8s_client_sg_id
}

output "ops_client_sg_id" {
  description = "Logical security group id for OPs tools (identity-only)."
  value       = module.security_groups.ops_client_sg_id
}

output "monitoring_client_sg_id" {
  description = "Logical security group id for Monitoring tools (identity-only)."
  value       = module.security_groups.monitoring_client_sg_id
}

output "breakglass_ssh_sg_id" {
  description = "Break-glass SSH SG id (no inbound by default; attach temporarily during emergency)."
  value       = module.security_groups.breakglass_ssh_sg_id
}
