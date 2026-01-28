output "bastion_sg_id" {
  value = aws_security_group.bastion.id
}
output "lb_public_sg_id" {
  value = aws_security_group.lb_public.id
}
output "k8s_cp_sg_id" {
  value = aws_security_group.k8s_cp.id
}
output "k8s_worker_sg_id" {
  value = aws_security_group.k8s_worker.id
}
output "db_sg_id" {
  value = aws_security_group.db.id
}
output "vpce_sg_id" {
  value = aws_security_group.vpce.id
}

output "breakglass_ssh_sg_id" {
  description = "Security group id for break-glass SSH (no inbound by default)."
  value       = aws_security_group.breakglass_ssh.id
}
