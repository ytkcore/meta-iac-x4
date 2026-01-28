################################################################################
# 55-bootstrap Stack Outputs
################################################################################

# -----------------------------------------------------------------------------
# ArgoCD Outputs
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# cert-manager Outputs
# -----------------------------------------------------------------------------
output "cert_manager_installed" {
  description = "cert-manager 설치 여부"
  value       = var.install_cert_manager
}

output "cert_manager_version" {
  description = "설치된 cert-manager 버전"
  value       = var.install_cert_manager ? var.cert_manager_version : "not installed"
}

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

# -----------------------------------------------------------------------------
# Connection Info
# -----------------------------------------------------------------------------
output "helm_repository_source" {
  description = "Helm 차트 설치 소스"
  value = {
    argocd      = local.argocd_repository
    certmanager = local.certmanager_repository
    rancher     = local.rancher_repository
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

[Helm Chart Source]
${local.harbor_oci_available ? "Harbor OCI: ${local.harbor_oci_url}" : "External Repositories (Internet)"}

[Get Initial Admin Password]
kubectl -n ${var.argocd_namespace} get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

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
