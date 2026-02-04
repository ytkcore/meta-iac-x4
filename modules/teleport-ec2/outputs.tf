output "instance_ids" {
  description = "Teleport instance IDs (list)"
  value       = [for i in module.instance : i.id]
}

output "instance_id" {
  description = "Primary Teleport instance ID (for backward compatibility)"
  value       = module.instance[0].id
}

output "private_ips" {
  description = "Teleport instance private IPs (list)"
  value       = [for i in module.instance : i.private_ip]
}

output "private_ip" {
  description = "Primary Teleport instance private IP (for backward compatibility)"
  value       = module.instance[0].private_ip
}

output "security_group_id" {
  value = aws_security_group.teleport.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.teleport_backend.name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.teleport_sessions.id
}

output "iam_role_names" {
  description = "EC2 instance IAM role names"
  value       = [for i in module.instance : i.iam_role_name]
}
