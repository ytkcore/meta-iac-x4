# T5: ArgoCD/Rancher/Longhorn Internal NLB 전환

> **Parent**: [클러스터 안정화](../2026-02-08-cluster-stabilization.md) | **Status**: ✅ 완료

## 📋 Summary

T3(Grafana/Vault)에 이어 나머지 관리 도구 3종(ArgoCD, Rancher, Longhorn)을 모두 Internal NLB로 전환. **Public NLB에서 관리 도구 완전 차단** 달성.

## 🔍 변경 전 상태

| 서비스 | 방식 | NLB | 위험 |
|--------|------|-----|------|
| ArgoCD | Terraform variable | Public | ❌ |
| Rancher | GitOps YAML | Public | ❌ |
| Longhorn | GitOps YAML | Public | ❌ |

## 🔧 변경

### Rancher
```yaml
# gitops-apps/bootstrap/rancher.yaml
rancher:
  ingress:
    ingressClassName: nginx-internal
```

### Longhorn
```yaml
# gitops-apps/bootstrap/longhorn.yaml
longhorn:
  ingress:
    ingressClassName: nginx-internal
```

### ArgoCD
ArgoCD는 다른 서비스와 달리 Terraform에서 직접 관리:
```hcl
# stacks/dev/55-bootstrap/variables.tf
variable "argocd_ingress_class" {
  default = "nginx-internal"    # ← nginx → nginx-internal
}
```
적용: `make apply STACK=55-bootstrap`

## ✅ 변경 후 — 최종 Ingress 현황

| 서비스 | Class | NLB | 접근 |
|--------|-------|-----|------|
| Keycloak 인증 API | `nginx` | **Public** | OIDC/SSO (필수) |
| Keycloak Admin | `nginx-internal` | Internal | 관리자 전용 |
| ArgoCD | `nginx-internal` | Internal | 관리자 전용 ✅ |
| Rancher | `nginx-internal` | Internal | 관리자 전용 ✅ |
| Longhorn | `nginx-internal` | Internal | 관리자 전용 ✅ |
| Grafana | `nginx-internal` | Internal | 관리자 전용 |
| Vault | `nginx-internal` | Internal | 관리자 전용 |

> **Public NLB에 남은 서비스**: Keycloak 인증 API만 (WAF 보호 적용)

## 🔧 변경 파일

| 파일 | 변경 | 커밋 |
|------|------|------|
| `gitops-apps/bootstrap/rancher.yaml` | ingressClassName | `067fd2a` |
| `gitops-apps/bootstrap/longhorn.yaml` | ingressClassName | `067fd2a` |
| `stacks/dev/55-bootstrap/variables.tf` | ArgoCD ingress_class default | `067fd2a` |

## 🏷️ Labels
`ingress`, `security`, `argocd`, `rancher`, `longhorn`, `internal-nlb`
