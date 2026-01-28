# =============================================================================
# GitOps App-of-Apps 구조 (ArgoCD)
# 
# 이 디렉토리를 Git 저장소에 푸시하고, Bastion에서 다음 명령으로 부트스트랩:
#   apply-argocd-apps https://github.com/<org>/<repo>.git gitops-apps/apps main
#
# 구조:
#   gitops-apps/
#   ├── apps/                    # Root App-of-Apps (ArgoCD Applications)
#   │   ├── cert-manager.yaml
#   │   ├── nginx-ingress.yaml
#   │   └── rancher.yaml
#   └── charts/                  # Helm values overrides
#       ├── cert-manager/
#       ├── nginx-ingress/
#       └── rancher/
# =============================================================================
