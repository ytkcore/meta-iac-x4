output "web_acl_id" {
  description = "Teleport WAF Web ACL ID"
  value       = module.teleport_waf.web_acl_id
}

output "web_acl_arn" {
  description = "Teleport WAF Web ACL ARN"
  value       = module.teleport_waf.web_acl_arn
}
