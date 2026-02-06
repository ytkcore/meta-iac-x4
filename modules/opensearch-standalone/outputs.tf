output "instance_id" {
  description = "OpenSearch EC2 instance ID"
  value       = module.instance.instance_id
}

output "private_ip" {
  description = "OpenSearch private IP address"
  value       = module.instance.private_ip
}

output "security_group_id" {
  description = "OpenSearch security group ID"
  value       = aws_security_group.this.id
}
