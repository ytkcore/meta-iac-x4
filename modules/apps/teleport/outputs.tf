output "user_data" {
  description = "Generated User Data script for Teleport EC2"
  value       = templatefile("${path.module}/user-data.sh", {
    cluster_name     = var.cluster_name
    region           = var.region
    dynamo_table     = aws_dynamodb_table.teleport_backend.name
    s3_bucket        = aws_s3_bucket.teleport_sessions.id
    email            = var.email
    teleport_version = var.teleport_version
    base_domain      = var.base_domain
    environment      = var.environment
  })
}

output "iam_instance_profile_name" {
  description = "IAM Instance Profile Name for EC2"
  value       = aws_iam_instance_profile.teleport.name
}

output "security_group_id" {
  description = "Security Group ID for EC2"
  value       = aws_security_group.teleport.id
}

output "web_target_group_arn" {
  description = "ARN of Web Target Group"
  value       = aws_lb_target_group.web.arn
}


