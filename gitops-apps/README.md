# =============================================================================
# GitOps App-of-Apps 구조 (ArgoCD)
# 
# 이 디렉토리를 Git 저장소에 푸시하고, Bastion에서 다음 명령으로 부트스트랩:
#   apply-argocd-apps https://github.com/<org>/<repo>.git gitops-apps/platform main
#
# 구조(권장):
#   gitops-apps/
#   ├── platform/                # Platform 레벨의 ArgoCD Applications (App-of-Apps 대상)
#   │   ├── rancher.yaml
#   │   ├── monitoring.yaml
#   │   └── longhorn.yaml
#   └── apps/                     # (선택) 예시/레거시 구조
# =============================================================================
