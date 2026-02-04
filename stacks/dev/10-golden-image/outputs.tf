# =============================================================================
# 10-golden-image Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# AMI Information
# -----------------------------------------------------------------------------
output "base_ami_id" {
  description = "Base Amazon Linux 2023 AMI ID"
  value       = data.aws_ami.al2023_base.id
}

output "golden_ami_id" {
  description = "Current Golden Image AMI ID (if exists)"
  value       = try(data.aws_ami.golden_existing.id, null)
}

output "golden_ami_name" {
  description = "Current Golden Image AMI Name"
  value       = try(data.aws_ami.golden_existing.name, null)
}

# -----------------------------------------------------------------------------
# Configuration Outputs (다른 스택에서 참조)
# -----------------------------------------------------------------------------
output "ssh_port" {
  description = "Configured SSH port"
  value       = var.ssh_port
}

output "docker_enabled" {
  description = "Docker default enabled state"
  value       = var.docker_enabled
}

output "cloudwatch_agent_enabled" {
  description = "CloudWatch Agent default enabled state"
  value       = var.cloudwatch_agent_enabled
}

output "teleport_agent_enabled" {
  description = "Teleport Agent default enabled state"
  value       = var.teleport_agent_enabled
}

# -----------------------------------------------------------------------------
# SSM Parameter ARNs (IAM 정책용)
# -----------------------------------------------------------------------------
output "ssm_parameter_ssh_port_arn" {
  description = "SSM Parameter ARN for SSH port"
  value       = aws_ssm_parameter.ssh_port.arn
}

output "ssm_parameter_cloudwatch_arn" {
  description = "SSM Parameter ARN for CloudWatch enabled"
  value       = aws_ssm_parameter.cloudwatch_enabled.arn
}



# -----------------------------------------------------------------------------
# Golden Image Configuration Summary
# -----------------------------------------------------------------------------
output "golden_image_config" {
  description = "Detailed Golden Image component configuration"
  value       = local.golden_image_config
}

output "golden_image_config_summary" {
  description = "Golden Image configuration summary"
  value = {
    base_os      = "Amazon Linux 2023"
    ssh_port     = var.ssh_port
    docker       = var.docker_enabled
    cloudwatch   = var.cloudwatch_agent_enabled
    teleport     = var.teleport_agent_enabled
    ssm          = true  # 항상 활성화
    ami_pattern  = local.ami_name_pattern
  }
}
