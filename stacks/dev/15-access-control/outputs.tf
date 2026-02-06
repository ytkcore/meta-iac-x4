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
