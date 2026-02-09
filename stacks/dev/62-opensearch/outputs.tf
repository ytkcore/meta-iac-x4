output "instance_id" {
  description = "OpenSearch EC2 instance ID"
  value       = module.opensearch.instance_id
}

output "private_ip" {
  description = "OpenSearch private IP address"
  value       = module.opensearch.private_ip
}

output "opensearch_fqdn" {
  description = "OpenSearch API FQDN (if Route53 record created)"
  value       = length(aws_route53_record.opensearch) > 0 ? aws_route53_record.opensearch[0].fqdn : null
}

output "dashboards_fqdn" {
  description = "OpenSearch Dashboards FQDN (if Route53 record created)"
  value       = length(aws_route53_record.opensearch_dashboards) > 0 ? aws_route53_record.opensearch_dashboards[0].fqdn : null
}

output "admin_password" {
  description = "OpenSearch admin password"
  value       = local.admin_password_effective
  sensitive   = true
}

output "opensearch_url" {
  description = "OpenSearch API URL"
  value       = length(aws_route53_record.opensearch) > 0 ? "https://${aws_route53_record.opensearch[0].fqdn}:9200" : "https://${module.opensearch.private_ip}:9200"
}

output "dashboards_url" {
  description = "OpenSearch Dashboards URL"
  value       = length(aws_route53_record.opensearch_dashboards) > 0 ? "http://${aws_route53_record.opensearch_dashboards[0].fqdn}:5601" : "http://${module.opensearch.private_ip}:5601"
}

# -----------------------------------------------------------------------------
# Access Gateway Integration (솔루션 독립적)
# -----------------------------------------------------------------------------
output "service_endpoint" {
  description = "Service endpoint for access-gateway integration (OpenSearch Dashboards)"
  value = length(aws_route53_record.opensearch_dashboards) > 0 ? {
    name     = "opensearch"
    uri      = "http://${aws_route53_record.opensearch_dashboards[0].fqdn}:5601"
    type     = "web"
    internal = true
  } : null
}
