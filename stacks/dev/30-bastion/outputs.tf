output "bastion_instance_id" {
  value = module.bastion.id
}

output "bastion_private_ip" {
  value = data.aws_instance.bastion.private_ip
}


output "bastion_az" {
  value = data.aws_instance.bastion.availability_zone
}

output "bastion_iam_role_name" {
  value = module.bastion.iam_role_name
}

# ==============================================================================
# 🚀 BASTION OPERATION GUIDE (SSM)
# ==============================================================================

output "Z_01_BASTION_LOGIN" {
  value = "💚 aws ssm start-session --target ${module.bastion.id}"
}

output "Z_02_INTERNAL_JUMP" {
  value = "💎 aws ssm start-session --target <INSTANCE_ID>"
}

output "Z_03_K8S_API_TUNNEL" {
  value = "🔒 aws ssm start-session --target ${module.bastion.id} --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters '{\"host\":[\"<RKE2_NLB_DNS>\"],\"portNumber\":[\"6443\"],\"localPortNumber\":[\"6443\"]}'"
}

output "Z_04_POSTGRES_TUNNEL" {
  value = "🐘 aws ssm start-session --target ${module.bastion.id} --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters '{\"host\":[\"postgres.${var.env}.${var.project}\"],\"portNumber\":[\"5432\"],\"localPortNumber\":[\"5432\"]}'"
}

output "Z_05_FILE_BRIDGE" {
  value = "📦 aws ssm start-session --target <ID> --document-name AWS-StartPortForwardingSession --parameters 'portNumber=[\"22\"],localPortNumber=[\"9999\"]'"
}
