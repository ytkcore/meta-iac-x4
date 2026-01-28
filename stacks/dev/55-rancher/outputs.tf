################################################################################
# 55-rancher Stack Outputs
################################################################################

output "rancher_url" {
  description = "Rancher 접속 URL"
  value       = module.rancher.rancher_url
}

output "rancher_hostname" {
  description = "Rancher hostname"
  value       = module.rancher.rancher_hostname
}

output "rancher_namespace" {
  description = "Rancher 네임스페이스"
  value       = module.rancher.rancher_namespace
}

output "cert_manager_namespace" {
  description = "cert-manager 네임스페이스"
  value       = module.rancher.cert_manager_namespace
}

output "rancher_version" {
  description = "설치된 Rancher 버전"
  value       = module.rancher.rancher_helm_release_version
}

output "cert_manager_version" {
  description = "설치된 cert-manager 버전"
  value       = module.rancher.cert_manager_helm_release_version
}

output "tls_source" {
  description = "TLS 인증서 소스"
  value       = module.rancher.tls_source
}

output "external_tls_termination" {
  description = "외부 TLS 종료 사용 여부"
  value       = module.rancher.external_tls_termination
}

output "cert_manager_installed" {
  description = "cert-manager 설치 여부"
  value       = module.rancher.cert_manager_installed
}

output "post_install_commands" {
  description = "설치 후 확인 명령어"
  value       = module.rancher.post_install_commands
}

output "next_steps" {
  description = "다음 단계 안내"
  value = <<-EOT
    
    ╔══════════════════════════════════════════════════════════════════════════════╗
    ║                         Rancher 설치 완료!                                   ║
    ╠══════════════════════════════════════════════════════════════════════════════╣
    ║                                                                              ║
    ║  1. Rancher 접속: ${module.rancher.rancher_url}
    ║                                                                              ║
    ║  2. 초기 로그인 후 반드시 비밀번호를 변경하세요!                               ║
    ║                                                                              ║
    ║  3. DNS 설정:                                                                ║
    ║     - Ingress NLB DNS를 ${module.rancher.rancher_hostname}에 연결하세요      ║
    ║     - 또는 /etc/hosts에 임시 등록                                            ║
    ║                                                                              ║
    ╠══════════════════════════════════════════════════════════════════════════════╣
    ║                        Day 2 Operations 권장사항                              ║
    ╠══════════════════════════════════════════════════════════════════════════════╣
    ║                                                                              ║
    ║  GitOps 전환 (권장):                                                         ║
    ║  - Rancher 내장 Fleet 활용: Continuous Delivery 메뉴                          ║
    ║  - 또는 ArgoCD 설치 후 Helm values Git 저장소 연동                            ║
    ║                                                                              ║
    ║  Rancher 설정 백업:                                                          ║
    ║  - Rancher UI > Global Settings > Backups 구성                               ║
    ║  - S3 또는 PV에 주기적 백업 설정                                              ║
    ║                                                                              ║
    ╚══════════════════════════════════════════════════════════════════════════════╝
  EOT
}
