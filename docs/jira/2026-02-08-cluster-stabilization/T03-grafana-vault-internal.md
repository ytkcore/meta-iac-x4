# T3: Grafana/Vault Ingress → Internal NLB 전환

> **Parent**: [클러스터 안정화](../2026-02-08-cluster-stabilization.md) | **Status**: ✅ 완료

## 📋 Summary

Grafana와 Vault 관리 UI를 Public NLB에서 Internal NLB로 전환하여 인터넷 노출을 제거. VPN/Teleport 경유 접근만 허용.

## 🔍 변경 전 상태

| 서비스 | ingressClassName | NLB | 노출 |
|--------|-----------------|-----|------|
| Grafana | `nginx` | Public | ❌ 인터넷 노출 |
| Vault | `nginx` | Public | ❌ 인터넷 노출 |

관리 도구가 Public NLB를 통해 직접 인터넷에 노출된 상태 → 보안 위험.

## 🔧 변경

### Grafana
```yaml
# gitops-apps/bootstrap/monitoring.yaml
grafana:
  ingress:
    ingressClassName: nginx-internal    # ← nginx → nginx-internal
```

### Vault
```yaml
# gitops-apps/bootstrap/vault.yaml
server:
  ingress:
    ingressClassName: nginx-internal    # ← nginx → nginx-internal
```

## ✅ 변경 후 상태

| 서비스 | ingressClassName | NLB | 접근 경로 |
|--------|-----------------|-----|----------|
| Grafana | `nginx-internal` | **Internal** | VPN/Teleport 전용 ✅ |
| Vault | `nginx-internal` | **Internal** | VPN/Teleport 전용 ✅ |

## 💡 설계 원칙

**관리 도구는 Internal NLB에만 바인딩**하는 것이 보안 표준:
- Public NLB: 사용자 대면 서비스만 (Keycloak 인증 API 등)
- Internal NLB: 관리/운영 도구 (Grafana, Vault, ArgoCD, Rancher, Longhorn)

## 🔧 변경 파일

| 파일 | 변경 | 커밋 |
|------|------|------|
| `gitops-apps/bootstrap/monitoring.yaml` | Grafana ingressClassName | `ffda789` |
| `gitops-apps/bootstrap/vault.yaml` | Vault ingressClassName | `ffda789` |

## 🏷️ Labels
`ingress`, `security`, `grafana`, `vault`, `internal-nlb`
