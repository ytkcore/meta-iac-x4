output "rke2_internal_nlb_dns" {
  description = "내부 NLB DNS"
  value       = module.rke2.rke2_internal_nlb_dns
}

output "control_plane_instance_ids" {
  description = "Control Plane 인스턴스 ID"
  value       = module.rke2.control_plane_instance_ids
}

output "worker_instance_ids" {
  description = "Worker 인스턴스 ID"
  value       = module.rke2.worker_instance_ids
}

output "rke2_token" {
  description = "RKE2 조인 토큰 (민감 정보)"
  value       = module.rke2.rke2_token
  sensitive   = true
}

output "nodes_security_group_id" {
  value = module.rke2.nodes_security_group_id
}

output "ingress_public_nlb_dns" {
  description = "Public Ingress NLB DNS (enable_public_ingress_nlb=true 일 때)"
  value       = module.rke2.ingress_public_nlb_dns
}

output "ingress_public_nlb_zone_id" {
  description = "Public Ingress NLB Hosted Zone ID (Route53 Alias용)"
  value       = module.rke2.ingress_public_nlb_zone_id
}

output "acm_certificate_arn" {
  description = "사용된 ACM 인증서 ARN"
  value       = module.rke2.acm_certificate_arn
}

################################################################################
# ACM / Ingress NLB debug outputs
################################################################################



output "effective_acm_certificate_arn" {
  description = "Ingress Public NLB(TLS)에 적용되는 최종 ACM 인증서 ARN"
  value       = local.effective_acm_certificate_arn
}

output "acm_tls_termination_enabled" {
  description = "Ingress Public NLB에서 ACM TLS 종료가 최종 활성화 되었는지"
  value       = local.effective_enable_acm_tls_termination
}

output "ingress_http_listener_enabled" {
  description = "Ingress Public NLB HTTP(80) listener 활성화 여부"
  value       = module.rke2.ingress_http_listener_enabled
}

output "ingress_http_listener_arn" {
  description = "Ingress Public NLB HTTP(80) listener ARN"
  value       = module.rke2.ingress_http_listener_arn
}

output "harbor_tfstate_found" {
  description = "S3에서 45-harbor.tfstate 존재 여부"
  value       = local.harbor_tfstate_found
}

output "harbor_effective_enabled" {
  description = "Harbor 연동 최종 활성화 여부"
  value       = local.effective_use_harbor
}

output "harbor_registry_hostport_effective" {
  description = "최종 적용된 Harbor registry host:port"
  value       = local.harbor_registry_hostport
}
