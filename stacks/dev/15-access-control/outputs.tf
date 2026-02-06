output "teleport_url" {
  value = "https://teleport.${var.base_domain}"
}

output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "instance_id" {
  value = module.ec2.instance_id
}

output "private_ip" {
  value = module.ec2.private_ip
}

# -----------------------------------------------------------------------------
# Access Gateway Integration
# -----------------------------------------------------------------------------
output "teleport_server" {
  description = "Teleport server information for access-gateway integration"
  value = {
    instance_id  = module.ec2.instance_id
    private_ip   = module.ec2.private_ip
    cluster_name = "teleport.${var.base_domain}"
    domain       = var.base_domain
  }
}
