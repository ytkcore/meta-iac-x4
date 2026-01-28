output "control_plane_instance_ids" {
  description = "Control Plane 인스턴스 ID"
  value       = { for k, v in aws_instance.control_plane : k => v.id }
}

output "worker_instance_ids" {
  description = "Worker 인스턴스 ID"
  value       = { for k, v in aws_instance.worker : k => v.id }
}

output "control_plane_private_ips" {
  description = "Control Plane Private IP"
  value       = { for k, v in aws_instance.control_plane : k => v.private_ip }
}

output "worker_private_ips" {
  description = "Worker Private IP"
  value       = { for k, v in aws_instance.worker : k => v.private_ip }
}

output "rke2_internal_nlb_dns" {
  description = "내부 NLB DNS (enable_internal_nlb=true 일 때)"
  value       = try(aws_lb.rke2[0].dns_name, null)
}

output "rke2_token" {
  description = "RKE2 조인 토큰 (민감 정보)"
  value       = local.token
  sensitive   = true
}

output "nodes_security_group_id" {
  description = "RKE2 노드 SG ID"
  value       = aws_security_group.nodes.id
}

output "ingress_public_nlb_dns" {
  description = "Public Ingress NLB DNS (enable_public_ingress_nlb=true 일 때)"
  value       = try(aws_lb.ingress[0].dns_name, null)
}

output "ingress_public_nlb_zone_id" {
  description = "Public Ingress NLB Hosted Zone ID (Route53 Alias용)"
  value       = try(aws_lb.ingress[0].zone_id, null)
}

output "ingress_public_nlb_arn" {
  description = "Public Ingress NLB ARN"
  value       = try(aws_lb.ingress[0].arn, null)
}

output "ingress_http_listener_enabled" {
  description = "Ingress Public NLB HTTP(80) listener 활성화 여부"
  value       = var.enable_public_ingress_nlb && var.enable_public_ingress_http_listener
}

output "ingress_http_listener_arn" {
  description = "Ingress Public NLB HTTP(80) listener ARN"
  value       = try(aws_lb_listener.ingress_http[0].arn, null)
}


output "acm_tls_termination_enabled" {
  description = "ACM TLS Termination 활성화 여부"
  value       = var.enable_acm_tls_termination
}

output "acm_certificate_arn" {
  description = "사용된 ACM 인증서 ARN (enable_acm_tls_termination=true 일 때)"
  value       = var.enable_acm_tls_termination ? var.acm_certificate_arn : null
}
