# -----------------------------------------------------------------------------
# Harbor EC2 Module Outputs
# -----------------------------------------------------------------------------

output "instance_id" {
  description = "EC2 Instance ID"
  value       = module.ec2.instance_id
}

output "private_ip" {
  description = "Private IP address of Harbor instance"
  value       = module.ec2.private_ip
}

output "security_group_id" {
  description = "Security Group ID"
  value       = aws_security_group.harbor.id
}

output "harbor_url" {
  description = "Harbor access URL"
  value       = var.enable_tls ? "https://${var.harbor_hostname}" : "http://${var.harbor_hostname}"
}

output "harbor_api_url" {
  description = "Harbor API URL"
  value       = var.enable_tls ? "https://${var.harbor_hostname}/api/v2.0" : "http://${var.harbor_hostname}/api/v2.0"
}

output "s3_bucket_id" {
  description = "S3 bucket ID for Harbor storage"
  value       = local.final_bucket_id
}

output "iam_role_name" {
  description = "IAM Role name attached to Harbor EC2"
  value       = module.ec2.iam_role_name
}

output "install_logs" {
  description = "Log paths for initial bootstrap/installation"
  value = {
    bootstrap = "/var/log/harbor-bootstrap.log"
    install   = "/var/log/harbor-install.log"
    marker    = "/opt/harbor/.installed"
  }
}

# -----------------------------------------------------------------------------
# ALB Outputs
# -----------------------------------------------------------------------------
output "alb_dns_name" {
  description = "ALB DNS name for Harbor access"
  value       = var.enable_alb ? aws_lb.harbor[0].dns_name : null
}

output "alb_zone_id" {
  description = "ALB hosted zone ID (for Route53 alias record)"
  value       = var.enable_alb ? aws_lb.harbor[0].zone_id : null
}

output "alb_arn" {
  description = "ALB ARN"
  value       = var.enable_alb ? aws_lb.harbor[0].arn : null
}

output "harbor_alb_url" {
  description = "Harbor URL via ALB"
  value       = var.enable_alb ? (var.alb_certificate_arn != null ? "https://${aws_lb.harbor[0].dns_name}" : "http://${aws_lb.harbor[0].dns_name}") : null
}

# -----------------------------------------------------------------------------
# Helm Chart OCI Registry Outputs
# -----------------------------------------------------------------------------
output "helm_oci_registry_url" {
  description = "Harbor OCI registry URL for Helm charts (use with oci:// prefix)"
  value       = "oci://${var.harbor_hostname}/helm-charts"
}

output "helm_oci_registry_insecure" {
  description = "Whether Helm OCI registry requires insecure connection"
  value       = !var.enable_tls
}

output "harbor_registry_hostport" {
  description = "Harbor registry host:port for container images"
  value       = var.enable_tls ? "${var.harbor_hostname}:443" : "${var.harbor_hostname}:80"
}

output "harbor_scheme" {
  description = "Harbor URL scheme (http/https)"
  value       = var.enable_tls ? "https" : "http"
}

output "harbor_proxy_cache_project" {
  description = "Name of the Docker Hub proxy cache project"
  value       = var.proxy_cache_project
}
