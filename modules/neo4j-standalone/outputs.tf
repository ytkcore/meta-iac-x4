output "instance_id" {
  value = module.instance.instance_id
}

output "private_ip" {
  value = module.instance.private_ip
}

output "security_group_id" {
  value = aws_security_group.this.id
}

output "bolt_uri" {
  value = "bolt://${module.instance.private_ip}:7687"
}

output "http_uri" {
  value = "http://${module.instance.private_ip}:7474"
}
