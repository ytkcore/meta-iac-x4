output "policy_arn" {
  description = "ALBC IAM Policy ARN"
  value       = aws_iam_policy.albc.arn
}

output "policy_name" {
  description = "ALBC IAM Policy 이름"
  value       = aws_iam_policy.albc.name
}
