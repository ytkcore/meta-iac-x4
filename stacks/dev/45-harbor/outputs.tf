output "instance_id" {
  description = "Instance ID for SSM deployment"
  value       = module.harbor.instance_id
}

output "harbor_endpoint" {
  description = "Harbor URL (via ALB)"
  value       = "${local.acm_certificate_arn != null ? "https" : "http"}://${local.final_hostname}"
}

output "s3_bucket" {
  description = "Harbor storage bucket name"
  value       = module.harbor.s3_bucket_id
}

# ---------------------------------------------------------------------------
# Backward-compatible outputs (consumed by 50-rke2 / 60-db stacks)
# ---------------------------------------------------------------------------
output "harbor_hostname" {
  # NOTE: 실제 Harbor hostname은 main.tf의 local.final_hostname을 사용합니다.
  value = local.final_hostname
}

output "harbor_scheme" {
  description = "Harbor URL scheme based on ACM certificate"
  value       = local.acm_certificate_arn != null ? "https" : "http"
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN used for ALB HTTPS (auto-discovered or explicit)"
  value       = local.acm_certificate_arn
}

output "harbor_registry_hostport" {
  description = "Harbor registry host:port for internal access (Private IP based)"
  value       = "${module.harbor.private_ip}:80"
}

output "harbor_registry_hostport_by_dns" {
  description = "Harbor registry host:port using DNS hostname (requires Route53 Private Zone)"
  value       = var.harbor_enable_tls ? "${local.final_hostname}:443" : "${local.final_hostname}:80"
}

output "harbor_private_ip" {
  description = "Harbor EC2 Private IP (for direct internal access)"
  value       = module.harbor.private_ip
}

output "harbor_proxy_cache_project" {
  value = var.harbor_proxy_cache_project
}

# -----------------------------------------------------------------------------
# Helm Chart OCI Registry Outputs (for 55-bootstrap)
# -----------------------------------------------------------------------------
output "helm_oci_registry_url" {
  description = "Harbor OCI registry URL for Helm charts (DNS/ALB HTTPS endpoint recommended)"
  value       = "oci://${local.final_hostname}/helm-charts"
}

output "helm_oci_registry_url_internal_ip" {
  description = "Harbor OCI registry URL using Private IP (HTTP-only 환경에서는 helm provider/argocd가 실패할 수 있어 권장되지 않음)"
  value       = "oci://${module.harbor.private_ip}/helm-charts"
}
output "helm_oci_registry_url_by_dns" {
  description = "Harbor OCI registry URL using DNS hostname"
  value       = "oci://${local.final_hostname}/helm-charts"
}

output "helm_oci_insecure" {
  description = "Whether Helm OCI registry requires --insecure-skip-tls-verify"
  value       = !var.harbor_enable_tls
}

output "harbor_route53_record_fqdn" {
  description = "Route53에 생성된 harbor CNAME 레코드(FQDN). enable_route53_harbor_cname=true 일 때 유효"
  value       = try(aws_route53_record.harbor_cname[0].fqdn, null)
}

output "harbor_alb_dns_name" {
  description = "Harbor ALB DNS name (Route53 CNAME target)"
  value       = module.harbor.alb_dns_name
}

output "harbor_cname_applied" {
  description = "Harbor ALB CNAME 적용 여부 및 상태"
  value = {
    enabled            = var.enable_route53_harbor_cname
    zone_id_discovered = local.route53_zone_id_effective != "" ? local.route53_zone_id_effective : null
    cname_created      = length(aws_route53_record.harbor_cname) > 0
    subdomain          = local.final_hostname
    target_alb_dns     = try(module.harbor.alb_dns_name, null)
  }
}

output "harbor_connection_info" {
  description = "Harbor 접속 및 DNS 설정 정보"
  value       = <<EOT

================================================================================
[Harbor Setup Complete]

1. Harbor URL : ${local.acm_certificate_arn != null ? "https" : "http"}://${local.final_hostname}
2. Admin Info : admin   

[Internal Resolution]
RKE2 노드에서 Harbor hostname(${local.final_hostname})을 내부망으로 해석할 수 있어야 합니다.
이 리포지토리는 **RKE2 노드 /etc/hosts에 자동으로 매핑(권장)** 하도록 구성할 수 있습니다.

[Route53 자동 등록]
- enable_route53_harbor_cname=true 이고 Hosted Zone이 지정(또는 자동 탐색)되면,
  harbor.${var.base_domain} CNAME -> ${module.harbor.alb_dns_name} 레코드가 자동으로 생성됩니다.
- disable 시에는 수동으로 CNAME을 등록하세요.
================================================================================
EOT
}

output "harbor_cname_fqdn" {
  description = "Expected Harbor FQDN (harbor.<base_domain>)"
  value       = local.final_hostname
}
