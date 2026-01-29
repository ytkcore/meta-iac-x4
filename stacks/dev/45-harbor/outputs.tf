# =============================================================================
# Outputs - Harbor Stack
# =============================================================================

# -----------------------------------------------------------------------------
# Core
# -----------------------------------------------------------------------------
output "instance_id" {
  description = "Harbor EC2 instance ID"
  value       = module.harbor.instance_id
}

output "harbor_endpoint" {
  description = "Harbor URL"
  value       = "${local.acm_certificate_arn != null ? "https" : "http"}://${local.final_hostname}"
}

output "harbor_hostname" {
  description = "Harbor FQDN"
  value       = local.final_hostname
}

output "harbor_scheme" {
  description = "Harbor internal scheme (for RKE2/internal access)"
  value       = var.harbor_enable_tls ? "https" : "http"
}

output "harbor_external_scheme" {
  description = "Harbor external scheme (ALB with ACM)"
  value       = local.acm_certificate_arn != null ? "https" : "http"
}

output "harbor_private_ip" {
  description = "Harbor EC2 private IP"
  value       = module.harbor.private_ip
}

# -----------------------------------------------------------------------------
# ALB / ACM
# -----------------------------------------------------------------------------
output "harbor_alb_dns_name" {
  description = "Harbor ALB DNS name"
  value       = module.harbor.alb_dns_name
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN (auto-discovered or explicit)"
  value       = local.acm_certificate_arn
}

# -----------------------------------------------------------------------------
# Route53
# -----------------------------------------------------------------------------
output "harbor_route53_fqdn" {
  description = "Route53 CNAME FQDN"
  value       = try(aws_route53_record.harbor_cname[0].fqdn, null)
}

output "harbor_cname_status" {
  description = "Route53 CNAME status"
  value = {
    enabled        = var.enable_route53_harbor_cname
    zone_id        = local.route53_zone_id != "" ? local.route53_zone_id : null
    cname_created  = length(aws_route53_record.harbor_cname) > 0
    target_alb_dns = local.harbor_alb_dns_name
  }
}

# -----------------------------------------------------------------------------
# Registry
# -----------------------------------------------------------------------------
output "harbor_registry_hostport" {
  description = "Harbor registry host:port (private IP)"
  value       = "${module.harbor.private_ip}:80"
}

output "harbor_registry_hostport_by_dns" {
  description = "Harbor registry host:port using DNS hostname (for RKE2 internal access)"
  value       = var.harbor_enable_tls ? "${local.final_hostname}:443" : "${local.final_hostname}:80"
}

output "harbor_proxy_cache_project" {
  description = "Docker Hub proxy cache project"
  value       = var.harbor_proxy_cache_project
}

# -----------------------------------------------------------------------------
# Helm OCI
# -----------------------------------------------------------------------------
output "helm_oci_registry_url" {
  description = "Helm OCI registry URL"
  value       = "oci://${local.final_hostname}/helm-charts"
}

output "helm_oci_insecure" {
  description = "Helm requires --insecure-skip-tls-verify"
  value       = local.acm_certificate_arn == null
}

# -----------------------------------------------------------------------------
# Storage
# -----------------------------------------------------------------------------
output "s3_bucket" {
  description = "Harbor S3 bucket name"
  value       = module.harbor.s3_bucket_id
}

# -----------------------------------------------------------------------------
# Connection Info
# -----------------------------------------------------------------------------
output "connection_info" {
  description = "Harbor connection summary"
  value       = <<-EOT

================================================================================
Harbor Setup Complete
================================================================================

  URL      : ${local.acm_certificate_arn != null ? "https" : "http"}://${local.final_hostname}
  Admin    : admin
  ALB DNS  : ${module.harbor.alb_dns_name}

  Route53 CNAME: ${var.enable_route53_harbor_cname ? "Enabled" : "Disabled"}
  Helm OCI     : oci://${local.final_hostname}/helm-charts

================================================================================
EOT
}
