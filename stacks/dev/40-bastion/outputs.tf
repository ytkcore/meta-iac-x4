output "bastion_instance_id" {
  value = module.bastion.id
}

output "bastion_public_ip" {
  value = data.aws_instance.bastion.public_ip
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

output "ssm_tunnel_command" {
  description = "Command to create a secure tunnel to the RKE2 cluster API"
  value       = <<EOT
# Create a local tunnel to K8s API (port 6443)
aws ssm start-session --target ${module.bastion.id} --region ${var.region} \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["<RKE2_Components_NLB_DNS_HERE>"],"portNumber":["6443"],"localPortNumber":["6443"]}'

# Then use kubectl locally
kubectl --server=https://127.0.0.1:6443 get nodes
EOT
}
