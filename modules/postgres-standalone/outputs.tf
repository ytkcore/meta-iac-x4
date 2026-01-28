output "instance_id" {
  value = module.instance.instance_id
}

output "private_ip" {
  value = module.instance.private_ip
}

output "security_group_id" {
  value = aws_security_group.this.id
}

output "connection" {
  value = "postgresql://${var.db_username}:***@${module.instance.private_ip}:5432/${var.db_name}"
}
