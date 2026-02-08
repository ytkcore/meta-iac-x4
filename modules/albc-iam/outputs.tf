output "policy_arn" {
  description = "ALBC IAM Policy ARN"
  value       = aws_iam_policy.albc.arn
}

output "policy_name" {
  description = "ALBC IAM Policy 이름"
  value       = aws_iam_policy.albc.name
}

output "vault_albc_role_arn" {
  description = "Vault AWS SE용 ALBC 전용 IAM Role ARN"
  value       = var.enable_vault_integration ? aws_iam_role.vault_albc[0].arn : ""
}
