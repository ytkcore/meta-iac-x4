################################################################################
# Rancher Module Outputs
################################################################################

output "rancher_hostname" {
  description = "Rancher 접속 URL (hostname)"
  value       = local.rancher_hostname
}

output "rancher_url" {
  description = "Rancher 접속 전체 URL"
  value       = "https://${local.rancher_hostname}"
}

output "rancher_namespace" {
  description = "Rancher가 설치된 네임스페이스"
  value       = kubernetes_namespace_v1.cattle_system.metadata[0].name
}

output "cert_manager_namespace" {
  description = "cert-manager가 설치된 네임스페이스 (external TLS 사용 시 null)"
  value       = local.install_cert_manager ? kubernetes_namespace_v1.cert_manager[0].metadata[0].name : null
}

output "rancher_helm_release_name" {
  description = "Rancher Helm 릴리스 이름"
  value       = helm_release.rancher.name
}

output "rancher_helm_release_version" {
  description = "Rancher Helm 차트 버전"
  value       = helm_release.rancher.version
}

output "cert_manager_helm_release_name" {
  description = "cert-manager Helm 릴리스 이름 (external TLS 사용 시 null)"
  value       = local.install_cert_manager ? helm_release.cert_manager[0].name : null
}

output "cert_manager_helm_release_version" {
  description = "cert-manager Helm 차트 버전 (external TLS 사용 시 null)"
  value       = local.install_cert_manager ? helm_release.cert_manager[0].version : null
}

output "tls_source" {
  description = "사용된 TLS 인증서 소스"
  value       = var.tls_source
}

output "external_tls_termination" {
  description = "외부 TLS 종료 사용 여부"
  value       = var.external_tls_termination || var.tls_source == "external"
}

output "cert_manager_installed" {
  description = "cert-manager 설치 여부"
  value       = local.install_cert_manager
}

output "bootstrap_password_notice" {
  description = "초기 비밀번호 안내"
  value       = "초기 로그인 후 반드시 비밀번호를 변경하세요."
}

output "post_install_commands" {
  description = "설치 후 확인 명령어"
  value = {
    check_rancher_pods    = "kubectl get pods -n cattle-system"
    check_certmanager     = local.install_cert_manager ? "kubectl get pods -n cert-manager" : "cert-manager not installed (external TLS)"
    check_rancher_ingress = "kubectl get ingress -n cattle-system"
    check_certificates    = local.install_cert_manager ? "kubectl get certificates -A" : "N/A (external TLS)"
    rancher_logs          = "kubectl logs -n cattle-system -l app=rancher --tail=100"
  }
}
