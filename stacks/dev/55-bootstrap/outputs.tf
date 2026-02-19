# ==============================================================================
# 55-bootstrap Outputs
# ==============================================================================

# ------------------------------------------------------------------------------
# ArgoCD Outputs
# ------------------------------------------------------------------------------
output "argocd_namespace" {
  description = "ArgoCD 설치 namespace"
  value       = var.argocd_namespace
}

output "argocd_server_nodeport" {
  description = "ArgoCD Server NodePort"
  value = {
    http  = var.argocd_nodeport_http
    https = var.argocd_nodeport_https
  }
}

output "argocd_initial_admin_password" {
  description = "ArgoCD 초기 관리자 비밀번호"
  value       = try(data.kubernetes_secret.argocd_initial_admin.data["password"], "")
  sensitive   = true
}

output "argocd_server_url" {
  description = "ArgoCD Server URL"
  value       = local.argocd_hostname != "" ? "https://${local.argocd_hostname}" : "Access via NodePort: ${var.argocd_nodeport_https}"
}

# Vault Auto-Unseal KMS
output "vault_kms_key_id" {
  description = "Vault Auto-Unseal KMS Key ID"
  value       = try(aws_kms_key.vault_unseal[0].key_id, "")
}


# -----------------------------------------------------------------------------
# cert-manager Outputs
# -----------------------------------------------------------------------------
# Cert-Manager outputs removed

# -----------------------------------------------------------------------------
# GitOps Outputs
# -----------------------------------------------------------------------------
output "gitops_enabled" {
  description = "GitOps App-of-Apps 활성화 여부"
  value       = var.enable_gitops_apps
}

output "gitops_repo_url" {
  description = "GitOps 저장소 URL"
  value       = var.enable_gitops_apps ? var.gitops_repo_url : ""
}

output "gitops_ssh_key_path" {
  description = "GitOps 저장소 접근용 SSH 키 경로"
  value       = var.enable_gitops_apps ? var.gitops_ssh_key_path : "N/A"
}

# -----------------------------------------------------------------------------
# Platform Credentials (90-credential-init Phase 1)
# - 배포 직후 관리자가 kubectl 없이 초기 비밀번호를 확인할 수 있도록 통합 output
# - ArgoCD-managed Secret은 최초 apply 시 비어있을 수 있음 (ArgoCD sync 완료 후 재조회)
# - Vault Root Token은 K8s Secret이 아님 → vault operator init 결과에서 확인
# - 사용법: terraform output -json platform_credentials
# -----------------------------------------------------------------------------
output "platform_credentials" {
  description = "플랫폼 초기 크리덴셜 (배포 후 관리자 콘솔 접근용)"
  sensitive   = true
  value = {
    argocd_admin_password   = try(data.kubernetes_secret.argocd_initial_admin.data["password"], "(not yet available)")
    grafana_admin_password  = try(data.kubernetes_secret.grafana_admin[0].data["admin-password"], "(not yet available)")
    keycloak_admin_password = try(data.kubernetes_secret.keycloak_admin[0].data["KEYCLOAK_ADMIN_PASSWORD"], "(not yet available)")
    vault_root_token        = "(vault operator init 결과에서 확인)"
    rancher_bootstrap       = "admin"
    harbor_default          = "Harbor12345"
  }
}

# -----------------------------------------------------------------------------
# Connection Info
# -----------------------------------------------------------------------------
output "helm_repository_source" {
  description = "Helm 차트 설치 소스"
  value = {
    argocd = local.argocd_repository
    # certmanager = local.certmanager_repository  <-- Removed
    # rancher     = local.rancher_repository      <-- Removed
    source_type = local.harbor_oci_available ? "harbor_oci" : "external"
  }
}

output "connection_info" {
  description = "ArgoCD 접속 정보"
  value       = <<-EOT

================================================================================
[Bootstrap Complete]

1. ArgoCD Namespace : ${var.argocd_namespace}
2. ArgoCD NodePort  : HTTP=${var.argocd_nodeport_http}, HTTPS=${var.argocd_nodeport_https}
3. ArgoCD URL       : ${local.argocd_hostname != "" ? "https://${local.argocd_hostname}" : "Use NodePort"}
4. Kubeconfig Path  : ${var.kubeconfig_path != null ? var.kubeconfig_path : "Using KUBECONFIG env var or default (~/.kube/config)"}

[Helm Chart Source]
${local.harbor_oci_available ? "Harbor OCI: ${local.harbor_oci_url}" : "External Repositories (Internet)"}

[Get Platform Credentials]
terraform output -json platform_credentials

[ArgoCD CLI Login (from Bastion)]
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
argocd login $NODE_IP:${var.argocd_nodeport_https} --username admin --password <PASSWORD> --insecure

[Change Admin Password]
argocd account update-password

%{if var.enable_gitops_apps}
[GitOps]
Repository : ${var.gitops_repo_url}
Branch     : ${var.gitops_repo_branch}
Path       : ${var.gitops_apps_path}
%{endif}
================================================================================
EOT
}
