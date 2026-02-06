output "teleport_url" {
  value = "https://${local.domain_name}"
}

output "alb_arn" {
  description = "Teleport ALB ARN (for WAF association)"
  value       = aws_lb.teleport.arn
}

output "instance_id" {
  value = module.teleport.instance_id
}

output "private_ip" {
  value = module.teleport.private_ip
}

