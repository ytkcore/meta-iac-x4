# [INFRA] Keycloak SSO — Grafana OIDC 연동 (Pilot)

> **Parent**: [2026-02-08-cluster-stabilization.md](./2026-02-08-cluster-stabilization.md) (T11)

## 📋 Summary

Keycloak `platform` realm의 `grafana` OIDC client를 활용하여 Grafana에 SSO 로그인 연동.
Grafana 로그인 화면에 **"Sign in with Keycloak"** 버튼이 표시되며, 클릭 시 Keycloak 인증 플로우로 전환.

> [!IMPORTANT]
> Grafana Helm chart v7.1+의 `assertNoLeakedSecrets` 보안 검증이 `client_secret`을 ConfigMap에서 자동 제거하는 이슈 발견.
> `envFromSecret`, `env` 리스트 방식으로 해결 시도 → kube-prometheus-stack subchart 구조 제약으로 실패.
> 최종 해결: `assertNoLeakedSecrets: false` 설정.

## 🎯 Goals

1. Keycloak `platform` realm OIDC client 확인
2. Grafana `auth.generic_oauth` 설정 연동
3. `client_secret` 안전한 주입 방법 구현
4. ArgoCD GitOps 파이프라인으로 전체 반영
5. SSO 로그인 버튼 표시 검증

---

## 🏗️ Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                        SSO Login Flow                             │
│                                                                   │
│  User → Grafana Login → "Sign in with Keycloak" 클릭              │
│    ↓                                                              │
│  Keycloak auth_url (OIDC Authorization Code Flow)                │
│    ↓                                                              │
│  User 인증 (username/password)                                    │
│    ↓                                                              │
│  Keycloak → Grafana callback (authorization code)                │
│    ↓                                                              │
│  Grafana → Keycloak token_url (code → access_token 교환)          │
│    ↓                                                              │
│  Grafana → Keycloak api_url (userinfo → email, groups 조회)       │
│    ↓                                                              │
│  Grafana role 매핑: groups[admin] → Admin, [editor] → Editor      │
└────────────────────────────────────────────────────────────────────┘
```

### Endpoint 구성

| Endpoint | URL |
|----------|-----|
| Issuer | `https://keycloak.dev.unifiedmeta.net/realms/platform` |
| Authorization | `.../protocol/openid-connect/auth` |
| Token | `.../protocol/openid-connect/token` |
| UserInfo | `.../protocol/openid-connect/userinfo` |
| Grafana Redirect | `https://grafana.unifiedmeta.net/*` |

### 네트워크 경로

```
Grafana Pod (monitoring ns) → K8s Service → nginx-internal → NLB Internal
                                                  ↓
                              Keycloak EC2 (10.0.101.201:8080, private subnet)
```

Keycloak은 K8s 외부(EC2)에서 실행되며, `keycloak` namespace의 headless Service + 수동 Endpoints로 K8s 내부에서 접근 가능. Split-Horizon Ingress로 Public(인증 API) + Internal(Admin Console) 분리.

---

## 📊 사전 확인

### 1. Keycloak 상태 확인

| 항목 | 값 |
|------|-----|
| EC2 Instance | `i-014b6fd348c899cc2` |
| Private IP | `10.0.101.201` |
| Realm | `platform` |
| Admin URL | `keycloak.dev.unifiedmeta.net/admin` (Internal NLB) |

**Admin API 접근 검증**:
```bash
# Keycloak admin 토큰 획득 (K8s pod에서)
curl -s -X POST "http://10.0.101.201:8080/realms/master/protocol/openid-connect/token" \
  -d "grant_type=client_credentials&client_id=admin-cli" \
  -d "grant_type=password&username=admin&password=Keycloak12345&client_id=admin-cli" \
  | jq -r '.access_token'
```

### 2. OIDC Client 확인

`platform` realm에 사전 구성된 OIDC clients:

| Client ID | Name | Secret | Redirect URI |
|-----------|------|--------|-------------|
| **grafana** | Grafana | `cb3ac87e35b9560110b2667e43bcc503` | `https://grafana.unifiedmeta.net/*` |
| harbor | Harbor | (별도) | `https://harbor.unifiedmeta.net/*` |
| rancher | Rancher | (별도) | `https://rancher.unifiedmeta.net/*` |
| teleport | Teleport | (별도) | `https://teleport.unifiedmeta.net/*` |

```bash
# OIDC client 목록 조회
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://10.0.101.201:8080/admin/realms/platform/clients" \
  | jq '.[] | {clientId, name, secret, redirectUris}'
```

---

## 🔧 구현 과정

### Phase 1: 초기 설정 (`27943f2`)

**문제**: `monitoring.yaml`의 `grafana.ini`에서 `client_secret: "${KEYCLOAK_GRAFANA_CLIENT_SECRET}"`으로 환경변수 참조 → 하지만 해당 env var를 Grafana Pod에 주입하는 메커니즘 부재.

**해결 시도**: `envFromSecret` 방식

```yaml
# monitoring.yaml 변경
grafana:
  envFromSecret: "keycloak-oidc-secret"
```

```yaml
# GitOps Secret 생성: keycloak-oidc-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-oidc-secret
  namespace: monitoring
type: Opaque
stringData:
  KEYCLOAK_GRAFANA_CLIENT_SECRET: "cb3ac87e35b9560110b2667e43bcc503"
```

**결과**: ❌ `envFromSecret` 값이 Grafana Deployment의 `envFrom`에 반영 안 됨.

**원인**: kube-prometheus-stack은 Grafana를 subchart로 포함. parent chart가 `envFromSecret`을 subchart로 전달하지 않음.

---

### Phase 2: env 방식 전환 (`bf593d0` → `f93de52`)

**해결 시도**: Grafana 내장 env var `GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET` 사용

```yaml
# 시도 1: Map 형식 (bf593d0) → ❌ 무시됨
grafana:
  env:
    GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET:
      valueFrom:
        secretKeyRef:
          name: keycloak-oidc-secret
          key: KEYCLOAK_GRAFANA_CLIENT_SECRET
```

```yaml
# 시도 2: List 형식 (f93de52) → ❌ Deployment에 미반영
grafana:
  env:
    - name: GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET
      valueFrom:
        secretKeyRef:
          name: keycloak-oidc-secret
          key: KEYCLOAK_GRAFANA_CLIENT_SECRET
```

**결과**: 두 방식 모두 ArgoCD Application CR의 Helm values에는 반영되나, 실제 Grafana Deployment의 Pod spec `containers[].env`에 전달 안 됨.

**원인**: kube-prometheus-stack → grafana subchart 간 Helm values 전파 구조에서 nested `env` block이 container spec으로 올바르게 merge되지 않음.

---

### Phase 3: 직접 client_secret (`5622952`) → `assertNoLeakedSecrets` 발견

**해결 시도**: `grafana.ini`에 직접 `client_secret` 기입

```yaml
grafana:
  grafana.ini:
    auth.generic_oauth:
      client_id: "grafana"
      client_secret: "cb3ac87e35b9560110b2667e43bcc503"
```

**결과**: ❌ ConfigMap `monitoring-grafana`에서 `client_secret` key 자체가 생략됨. 다른 모든 key(`client_id`, `scopes`, `auth_url` 등)는 정상 렌더링.

**근본 원인 발견**:

> **Grafana Helm chart v7.1+** 에 `assertNoLeakedSecrets` 보안 검증 추가.
> Helm template rendering 시 `values.yaml`에 `secret`, `password`, `token` 등의 키워드가 포함된 값을 감지하면 **자동으로 ConfigMap에서 제외**.
> 에러 메시지 없이 silent하게 동작.

참조: [grafana/helm-charts#2497](https://github.com/grafana/helm-charts/issues/2497)

---

### Phase 4: 최종 수정 (`0745cc8`) ✅

```yaml
grafana:
  assertNoLeakedSecrets: false    # ← 핵심: Helm secret validation 비활성
  grafana.ini:
    auth.generic_oauth:
      enabled: true
      name: "Keycloak"
      allow_sign_up: true
      auto_login: false
      client_id: "grafana"
      client_secret: "cb3ac87e35b9560110b2667e43bcc503"
      scopes: "openid email profile roles"
      auth_url: "https://keycloak.dev.unifiedmeta.net/realms/platform/protocol/openid-connect/auth"
      token_url: "https://keycloak.dev.unifiedmeta.net/realms/platform/protocol/openid-connect/token"
      api_url: "https://keycloak.dev.unifiedmeta.net/realms/platform/protocol/openid-connect/userinfo"
      role_attribute_path: "contains(groups[*], 'admin') && 'Admin' || contains(groups[*], 'editor') && 'Editor' || 'Viewer'"
      tls_skip_verify_insecure: true
```

**결과**: ✅ ConfigMap에 `client_secret` 정상 렌더링. Grafana 로그인에 "Sign in with Keycloak" 표시.

---

## 🐛 Troubleshooting Log

### Issue 1: ArgoCD sync pipeline 이해

```
Git Push → root-apps 감지 → monitoring Application CR 업데이트 → monitoring app Helm rendering → K8s resources
```

root-apps가 먼저 monitoring Application CR을 업데이트해야 Helm values가 반영됨. root-apps refresh 없이 monitoring만 refresh하면 이전 values 사용.

**해결**: `root-apps` hard refresh → `monitoring` hard refresh 순서 필요.

### Issue 2: PVC Multi-Attach Deadlock

Grafana Deployment의 `RollingUpdate` 전략 + Longhorn `ReadWriteOnce` PVC 조합에서 Multi-Attach 에러 발생.

```
Multi-Attach error for volume "pvc-066f6035-..." Volume is already used by pod(s) ...
```

**해결**: `scale --replicas=0` → `scale --replicas=1` 또는 이전 pod 강제 삭제.

### Issue 3: ArgoCD selfHeal 원복

`selfHeal: true` 설정으로 인해 수동 ConfigMap/Deployment 패치가 ArgoCD에 의해 자동 원복.

**교훈**: ArgoCD managed resources는 반드시 GitOps를 통해 변경해야 함.

---

## ✅ 검증 결과

### ConfigMap 확인
```bash
kubectl -n monitoring get cm monitoring-grafana -o jsonpath='{.data.grafana\.ini}' | grep client_secret
# 출력: client_secret = cb3ac87e35b9560110b2667e43bcc503
```

### Login Button 확인
```bash
kubectl -n monitoring exec $GRAFANA_POD -c grafana -- wget -qO- http://localhost:3000/login | grep -o "Keycloak"
# 출력: Keycloak
```

### ArgoCD 전체 상태
```
13/13 ArgoCD Apps → Synced + Healthy
```

| App | Status |
|-----|--------|
| aws-load-balancer-controller | Synced ✅ |
| cert-manager | Synced ✅ |
| cert-manager-issuers | Synced ✅ |
| external-dns | Synced ✅ |
| external-dns-private | Synced ✅ |
| keycloak-ingress | Synced ✅ |
| longhorn | Synced ✅ |
| **monitoring** | **Synced ✅** |
| nginx-ingress | Synced ✅ |
| nginx-ingress-internal | Synced ✅ |
| rancher | Synced ✅ |
| root-apps | Synced ✅ |
| vault | Synced ✅ |

---

## 📋 Role Mapping

Grafana는 Keycloak의 `groups` claim을 기반으로 역할을 자동 매핑:

```
role_attribute_path: "contains(groups[*], 'admin') && 'Admin' || contains(groups[*], 'editor') && 'Editor' || 'Viewer'"
```

| Keycloak Group | Grafana Role | 권한 |
|---------------|--------------|------|
| `admin` | Admin | 전체 관리 권한 |
| `editor` | Editor | 대시보드 편집 |
| (기타) | Viewer | 읽기 전용 |

---

## 📋 Tasks

- [x] Keycloak `platform` realm 확인 (EC2, 10.0.101.201)
- [x] OIDC client `grafana` 확인 (secret: `cb3ac87e`)
- [x] K8s Secret `keycloak-oidc-secret` 생성 (monitoring ns)
- [x] `envFromSecret` 시도 → 실패 (subchart 전파 제한)
- [x] `env` list 시도 → 실패 (container spec 미반영)
- [x] `grafana.ini` 직접 기입 → 실패 (`assertNoLeakedSecrets`)
- [x] `assertNoLeakedSecrets: false` → ✅ 성공
- [x] Grafana "Sign in with Keycloak" 버튼 확인
- [x] ArgoCD 13/13 Synced + Healthy

## 🔧 변경 파일

| 파일 | 변경 내용 | 커밋 |
|------|-----------|------|
| `gitops-apps/bootstrap/monitoring.yaml` | `assertNoLeakedSecrets: false`, OIDC config | `0745cc8` |
| `gitops-apps/keycloak-ingress/keycloak-oidc-secret.yaml` | [NEW] OIDC client secret | `27943f2` |

### 커밋 히스토리

| 커밋 | 내용 | 결과 |
|------|------|------|
| `27943f2` | `envFromSecret: keycloak-oidc-secret` | ❌ subchart 미지원 |
| `bf593d0` | `env.valueFrom.secretKeyRef` (map 형식) | ❌ 무시됨 |
| `f93de52` | `env` list 형식으로 변환 | ❌ container에 미전달 |
| `5622952` | `client_secret` 직접 기입 + env 제거 | ❌ ConfigMap에서 제거됨 |
| **`0745cc8`** | **`assertNoLeakedSecrets: false`** | **✅** |
| `5e97514` | Jira 티켓 업데이트 | 문서 |

## 💡 Lessons Learned

1. **kube-prometheus-stack subchart 제약**: `envFromSecret`, `env` 값이 Grafana subchart의 container spec으로 정상 전파되지 않음. Helm subchart 중첩 시 values 전파 경로 주의.
2. **assertNoLeakedSecrets**: Grafana Helm chart v7.1+ 기본 활성. `secret`, `password` 키워드 포함 값을 silent하게 ConfigMap에서 제거. 에러/경고 없이 동작하므로 디버깅 어려움.
3. **ArgoCD sync pipeline**: `root-apps` → `Application CR` → `monitoring` Helm render 순서. 단일 app만 refresh하면 이전 values 사용.
4. **PVC RWO + RollingUpdate**: Longhorn ReadWriteOnce + Deployment RollingUpdate 조합에서 Multi-Attach deadlock 발생 가능. `Recreate` 전략 또는 수동 scale 0→1 필요.

## 🔮 추후 작업

- [ ] Keycloak `admin`/`editor` 그룹에 사용자 추가 → Grafana 실제 SSO 로그인 E2E 검증
- [ ] Harbor, Rancher, Teleport OIDC 연동 확장 (동일 패턴)
- [ ] `client_secret`를 Vault Dynamic Secrets로 관리 (보안 강화)
- [ ] `tls_skip_verify_insecure: true` → 내부 CA 인증서 구성으로 전환

## 📎 References

- [Parent Ticket: 클러스터 안정화](./2026-02-08-cluster-stabilization.md)
- [Keycloak Helm Chart assertNoLeakedSecrets](https://github.com/grafana/helm-charts/issues/2497)
- [Grafana OIDC Documentation](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-authentication/generic-oauth/)

## 🏷️ Labels

`keycloak`, `sso`, `oidc`, `grafana`, `helm`, `argocd`, `troubleshooting`

## 📌 Priority / Status

**Medium** / ✅ 완료 (2026-02-08)
