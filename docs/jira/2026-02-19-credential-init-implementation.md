# 90-credential-init — ESO + SSO 인프라 구현

> **날짜**: 2026-02-19  
> **상태**: ✅ 코드 완료 (E2E 검증 대기)  
> **라벨**: `security`, `vault`, `sso`, `eso`, `v0.6`  
> **우선순위**: High  
> **선행**: [credential-bootstrap-strategy](2026-02-13-credential-bootstrap-strategy.md) (전략 확정)

---

## 목표

Vault + ESO(External Secrets Operator)를 통한 OIDC Client Secret 중앙 관리 인프라 구축 및 전 서비스 SSO 연동.

## 구현 범위

### Phase 1: 크리덴셜 Discovery

| 파일 | 변경 |
|------|------|
| `55-bootstrap/main.tf` | `data.kubernetes_secret` 추가 (Grafana, Keycloak) |
| `55-bootstrap/outputs.tf` | `platform_credentials` 통합 output 추가 |
| `scripts/common/credentials.sh` | terraform output 우선 → kubectl fallback 전면 재작성 |

### Phase 2: ESO 인프라 배포

| 파일 | 변경 |
|------|------|
| `gitops-apps/bootstrap/external-secrets.yaml` | ESO ArgoCD App (sync-wave: 25, chart 0.12.1) |
| `gitops-apps/platform/vault-secret-store.yaml` | ClusterSecretStore (Vault K8s Auth) |
| `scripts/credential-init/vault-seed.sh` | Vault KV + K8s Auth + Policy + Role 자동 설정 |

### Phase 3: OIDC Secret 관리 + SSO 연동

| 파일 | 변경 |
|------|------|
| `gitops-apps/platform/external-secrets/*.yaml` | ExternalSecret 4개 (ArgoCD, Grafana, Harbor, Rancher) |
| `55-bootstrap/templates/argocd-values.yaml.tftpl` | `clientSecret` → `$argocd-oidc-secret:oidc.keycloak.clientSecret` |
| `gitops-apps/bootstrap/monitoring.yaml` | `envFromSecret` → `grafana-oidc-secret` |

### Phase 4: 문서화

| 파일 | 변경 |
|------|------|
| `docs/guides/post-deployment-operations-guide.md` | terraform output Quick Ref + Day-1 시나리오 + ESO 흐름 + break-glass |

## 아키텍처

```
Vault KV (secret/platform/oidc/*)
  ↕ K8s Auth (external-secrets SA)
ESO (ClusterSecretStore: vault-backend)
  ↓ ExternalSecret (1h refresh)
K8s Secret (namespace별)
  ↓ envFrom / $secret:key
서비스 SSO (ArgoCD, Grafana, Harbor, Rancher)
```

## E2E 검증 체크리스트

- [ ] `terraform apply` → `platform_credentials` 출력 확인
- [ ] `vault-seed.sh` → K8s Auth/Policy/Role 생성
- [ ] ESO ArgoCD sync → healthy
- [ ] Keycloak OIDC Client 생성 → `vault kv put`
- [ ] ExternalSecret → K8s Secret 동기화
- [ ] SSO 로그인 검증 (ArgoCD, Grafana)
- [ ] break-glass 검증 (로컬 admin)

## 커밋 수

- 신규 파일: 7개
- 수정 파일: 3개
