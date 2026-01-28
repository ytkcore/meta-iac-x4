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

output "ssm_start_session_command" {
  description = "Run on your local machine to open an SSM Session Manager shell into the bastion."
  value       = "aws ssm start-session --target ${module.bastion.id} --region ${var.region}"
}

output "bootstrap_quickstart" {
  description = "Quick start commands for ArgoCD + Rancher GitOps setup"
  value = <<-EOT
    # =============================================================================
    # GitOps 부트스트랩 가이드
    # =============================================================================
    
    # 1) SSM 세션 시작
    aws ssm start-session --target ${module.bastion.id} --region ${var.region}
    
    # 2) Bastion 내부에서 실행:
    
    # 2-1) RKE2 kubeconfig 가져오기
    fetch-rke2-kubeconfig
    
    # 2-2) ArgoCD 설치 (NodePort 모드 - Public NLB 연결용)
    bootstrap-argocd argocd argocd NodePort ${var.argocd_nodeport}
    
    # 2-3) GitOps App-of-Apps 적용 (Rancher 포함)
    # Git 저장소에 gitops-apps/ 디렉토리를 푸시한 후:
    apply-argocd-apps https://github.com/<org>/<repo>.git gitops-apps/apps main
    
    # =============================================================================
    # 접속 정보
    # =============================================================================
    # ArgoCD UI: https://<PUBLIC_NLB_DNS>:${var.argocd_nodeport}
    # Rancher UI: https://<rancher.hostname> (DNS 설정 필요)
    #
    # ArgoCD 초기 비밀번호:
    #   kubectl -n argocd get secret argocd-initial-admin-secret \
    #     -o jsonpath='{.data.password}' | base64 -d; echo
  EOT
}
