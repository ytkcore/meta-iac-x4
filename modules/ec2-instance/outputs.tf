output "id" {
  description = "The ID of the EC2 instance"
  value       = aws_instance.this.id
}

output "instance_id" {
  description = "The ID of the EC2 instance (alias)"
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Private IP address of the instance"
  value       = aws_instance.this.private_ip
}

output "iam_role_name" {
  description = "The name of the IAM role (for attaching extra policies) - null if using external profile"
  value       = length(aws_iam_role.this) > 0 ? aws_iam_role.this[0].name : null
}

