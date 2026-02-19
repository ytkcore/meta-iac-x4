# 구축 후 운영 초기화 가이드 (Post-Deployment Operations Guide)

> **기준 시점**: v0.6 아키텍처  
> **최종 업데이트**: 2026-02-19  
> **전제**: 전체 스택 배포 완료 + Teleport를 통한 서비스 접근 가능 상태

---

## 🔑 Quick Reference — 초기 Credential 조회

> **글로벌 표준**: kubectl 없이 `terraform output`으로 초기 비밀번호를 즉시 확인할 수 있습니다.

```bash
# 방법 1: terraform output (권장 — kubectl 불필요)
aws-vault exec <profile> -- terraform -chdir=stacks/dev/55-bootstrap output -json platform_credentials

# 방법 2: make wrapper
aws-vault exec <profile> -- make credentials-show
```

| 서비스 | 계정 | 조회 방법 | 비고 |
|--------|------|----------|------|
| Vault | `root` | `vault operator init` 결과 | KMS Auto-unseal |
| Keycloak | `admin` | `terraform output` | 수동 Secret 생성 |
| ArgoCD | `admin` | `terraform output` | Helm 자동 생성 |
| Grafana | `admin` | `terraform output` | Helm 자동 생성 |
| Rancher | `admin` | `terraform output` | 기본값 `admin` |
| Harbor | `admin` | 기본값: `Harbor12345` ⚠️ | 즉시 변경 |
| AIPP | `admin@en-core.com` | 기본값: `Admin1234!` ⚠️ | 즉시 변경 |

> [!CAUTION]
> ⚠️ 표시된 하드코딩 비밀번호는 **첫 로그인 즉시 변경** 필수.  
> Secret 기반 비밀번호도 초기화 완료 후 Secret 삭제 권장 (§8 참조).

---

## 🔐 90-credential-init — SSO 자동화 워크플로우

> **Phase 90**: 전 서비스 배포 완료 후, Vault + ESO를 통해 OIDC Secret을 중앙 관리하고 SSO를 활성화합니다.

### Day-1 관리자 시나리오

| 단계 | 작업 | 도구 |
|:---:|------|------|
| 1 | `terraform apply` (스택 00~80) | Terraform |
| 2 | `terraform output platform_credentials` → 초기 PW 확보 | Terraform |
| 3 | Vault Unseal 확인 (KMS 자동) | Vault CLI |
| 4 | `vault-seed.sh` 실행 → K8s Auth + Policy 설정 | `scripts/credential-init/vault-seed.sh` |
| 5 | Keycloak 로그인 → `platform` Realm + OIDC Client 생성 | Keycloak UI |
| 6 | `vault kv put` → OIDC Client Secret을 Vault에 저장 | Vault CLI |
| 7 | ESO + ExternalSecret ArgoCD auto-sync 확인 | ArgoCD UI |
| 8 | SSO 로그인 검증 (ArgoCD, Grafana) | 브라우저 |
| 9 | break-glass 검증 (Keycloak 중지 → 로컬 admin 접근) | kubectl |
| 10 | 초기 Secret 정리 + MFA 활성화 | Keycloak UI |

### ESO Secret 동기화 흐름

```
Vault KV (secret/platform/oidc/*)  →  ESO (1h 주기)  →  K8s Secret (namespace별)
  argocd: client-secret              argocd-oidc-secret     (argocd ns)
  grafana: client-secret             grafana-oidc-secret    (monitoring ns)
  harbor: client-secret              harbor-oidc-secret     (harbor ns)
  rancher: client-secret             rancher-oidc-secret    (cattle-system ns)
```

### break-glass 접근 (SSO 장애 시)

| 서비스 | 로컬 admin | 방법 |
|--------|:--------:|------|
| ArgoCD | ✅ | `admin` + `argocd-initial-admin-secret` |
| Grafana | ✅ | `admin` + `monitoring-grafana-secret` |
| Harbor | ✅ | `admin` + 변경된 비밀번호 |
| Rancher | ✅ | `admin` + 변경된 비밀번호 |
| Longhorn | ✅ | basic-auth (OIDC 미지원) |

---

## 개요

전체 인프라 배포 완료 후, 각 서비스의 **어드민 계정 확보 → 기본 운영 설정 → SSO 연동 → 검증** 순서로 초기화를 진행합니다.

### 서비스 초기화 우선순위

| 순서 | 서비스 | 역할 | 초기화 이유 |
|:---:|--------|------|-----------|
| 1 | **Vault** | Secret 관리 | 모든 서비스의 Secret 주입 기반 |
| 2 | **Keycloak** | SSO / IdP | 나머지 서비스 인증 연동의 전제 |
| 3 | **ArgoCD** | GitOps | 앱 배포/동기화 상태 관리 |
| 4 | **Grafana** | 모니터링 | 클러스터 및 서비스 관측 |
| 5 | **Harbor** | 이미지 레지스트리 | 이미지 관리 + 취약점 스캔 |
| 6 | **Rancher** | 클러스터 관리 | 멀티 클러스터 관리 UI |
| 7 | **AIPP** | 고객 서비스 | 비즈니스 애플리케이션 |

> [!IMPORTANT]
> **Vault → Keycloak** 순서가 핵심입니다.
> Vault가 Sealed 상태면 Keycloak DB 비밀번호를 조회할 수 없고, Keycloak이 없으면 다른 서비스의 SSO 연동이 불가합니다.

### Teleport 접근 경로

모든 관리 UI는 Teleport App Access를 통해 접근합니다:

| 서비스 | 접근 URL |
|--------|---------|
| ArgoCD | `https://argocd.teleport.<domain>` |
| Grafana | `https://grafana.teleport.<domain>` |
| Harbor | `https://harbor.teleport.<domain>` |
| Rancher | `https://rancher.teleport.<domain>` |
| Longhorn | `https://longhorn.teleport.<domain>` |

---

## 1. Vault 초기화

### 1.1 상태 확인

```bash
kubectl exec -n vault vault-0 -- vault status
```

| 상태 | 의미 | 조치 |
|------|------|------|
| `Sealed: true` | Vault 잠김 | Unseal 키로 해제 필요 |
| `Sealed: false` | 정상 | 다음 단계 진행 |
| Pod 없음 | 미배포 | ArgoCD에서 vault 앱 sync |

### 1.2 필수 설정

- [ ] Root Token 확보 및 안전한 곳에 보관
- [ ] KV Secrets Engine 활성화 확인 (`vault secrets list`)
- [ ] AppRole / K8s Auth Method 구성 확인
- [ ] Keycloak DB 비밀번호 Secret 존재 확인
- [ ] OIDC Client Secret 저장 경로 생성:
  ```bash
  vault kv put secret/platform/oidc \
    argocd-client-secret="<생성 후 입력>" \
    grafana-client-secret="<생성 후 입력>" \
    harbor-client-secret="<생성 후 입력>"
  ```

### 1.3 검증

```bash
kubectl exec -n vault vault-0 -- vault kv get secret/keycloak/db
```

- [ ] ✅ Vault Active + Secret 조회 성공

> **⚠️ 실패 시**: Pod CrashLoopBackOff → Unseal 키 분실 여부 확인. AWS KMS seal 사용 시 KMS 키 접근 권한(IAM Role) 점검.

---

## 2. Keycloak 초기화

> **SSO 연동의 기반**. 이 단계가 완료되어야 ArgoCD, Grafana, Harbor의 SSO 설정이 가능합니다.

### 2.1 Admin 접근

Admin Console 접속: Teleport → Keycloak → `admin` / Quick Reference 테이블 비밀번호

### 2.2 Realm 설정

- [ ] `platform` Realm 생성 (또는 존재 확인)
- [ ] Realm 기본 설정:
  - Login Theme 설정
  - Token Lifespan 조정 (Access: 5m, SSO Session: 8h)
  - Brute Force Detection 활성화
  - **Password Policy**: 최소 12자, 대소문자+숫자+특수문자

### 2.3 사용자 계정 생성

- [ ] 관리자 사용자 계정 생성
- [ ] **Temporary Password** 옵션 활성화 → 첫 로그인 시 비밀번호 변경 강제
- [ ] 그룹 생성: `admins`, `developers`, `viewers`
- [ ] 그룹별 역할 매핑

> **글로벌 표준 (Rancher/Grafana 패턴)**: 초기 계정은 반드시 `Temporary Password`로 발급하여 첫 로그인 시 변경을 강제합니다.

### 2.4 SSO Client 등록

각 서비스별 OIDC Client를 생성합니다:

| Client ID | 대상 서비스 | Redirect URI |
|-----------|-----------|-------------|
| `argocd` | ArgoCD | `https://argocd.<domain>/auth/callback` |
| `grafana` | Grafana | `https://grafana.<domain>/login/generic_oauth` |
| `harbor` | Harbor | `https://harbor.<domain>/c/oidc/callback` |

각 Client 설정:
- Client Protocol: `openid-connect`
- Access Type: `confidential`
- Valid Redirect URIs: 위 표 참조
- Client Secret 생성 → **Vault에 저장** (§1.2 경로 참조)

> **글로벌 표준 (HashiCorp Best Practice)**: OIDC Client Secret은 수동 복사하지 않고 Vault KV에 중앙 저장합니다.
> ```
> vault kv put secret/platform/oidc \
>   argocd-client-secret="<ArgoCD client secret>" \
>   grafana-client-secret="<Grafana client secret>" \
>   harbor-client-secret="<Harbor client secret>"
> ```

### 2.5 검증

- [ ] ✅ Admin Console 로그인 성공
- [ ] ✅ `platform` Realm 존재 + Client 목록 확인
- [ ] ✅ OIDC Discovery URL 응답 확인:
  ```
  curl https://keycloak.<domain>/realms/platform/.well-known/openid-configuration
  ```

> **⚠️ 실패 시**: Keycloak Pod 로그 확인 → DB 연결 실패가 대부분. Vault에서 DB Secret 존재 여부 재확인.

---

## 3. ArgoCD 초기화

### 3.1 Admin 접근

ArgoCD UI 접속: Teleport → ArgoCD → `admin` / Quick Reference 테이블 비밀번호

### 3.2 필수 설정

- [ ] Admin 비밀번호 변경
- [ ] Git Repository 연결 확인 (Private repo → SSH key 또는 HTTPS token)
- [ ] Application 상태 점검 — 전체 앱 `Healthy` / `Synced` 확인

### 3.3 Keycloak SSO 연동

`argocd-cm` ConfigMap에 OIDC 설정 추가:

```yaml
data:
  url: https://argocd.<domain>
  oidc.config: |
    name: Keycloak
    issuer: https://keycloak.<domain>/realms/platform
    clientID: argocd
    clientSecret: $oidc.keycloak.clientSecret
    requestedScopes: ["openid", "profile", "email", "groups"]
```

> Client Secret은 Vault에서 조회: `vault kv get secret/platform/oidc`

### 3.4 RBAC 설정

- [ ] `argocd-rbac-cm`에서 그룹별 권한 매핑
- [ ] 기본 정책: `role:readonly` → Keycloak `admins` 그룹만 `role:admin`

### 3.5 검증

- [ ] ✅ SSO 로그인 성공 (Keycloak → ArgoCD)
- [ ] ✅ 전체 Application `Healthy` 상태

> **⚠️ 실패 시**: OIDC callback 에러 → Redirect URI 불일치 확인. `issuer` URL이 Teleport 프록시 경유가 아닌 내부 DNS로 해석되는지 확인.

---

## 4. Grafana 초기화

### 4.1 Admin 접근

Grafana UI: Teleport → Grafana → `admin` / Quick Reference 테이블 비밀번호

### 4.2 Keycloak SSO 연동

Grafana Helm values에 OIDC 설정:

```yaml
grafana.ini:
  auth.generic_oauth:
    enabled: true
    name: Keycloak
    client_id: grafana
    client_secret: <vault에서 조회>
    auth_url: https://keycloak.<domain>/realms/platform/protocol/openid-connect/auth
    token_url: https://keycloak.<domain>/realms/platform/protocol/openid-connect/token
    api_url: https://keycloak.<domain>/realms/platform/protocol/openid-connect/userinfo
    scopes: openid profile email
    role_attribute_path: contains(groups[*], 'admins') && 'Admin' || 'Viewer'
```

### 4.3 Datasource 확인

- [ ] Prometheus 연결 확인 (`http://prometheus-operated:9090`)
- [ ] Loki 연결 확인 (설치된 경우)
- [ ] AlertManager 연결 확인

### 4.4 대시보드

- [ ] Node Exporter Full 대시보드 임포트 (ID: 1860)
- [ ] K8s Cluster Overview 대시보드 임포트 (ID: 15520)
- [ ] AIPP 서비스 커스텀 대시보드 생성

### 4.5 검증

- [ ] ✅ SSO 로그인 성공
- [ ] ✅ Prometheus 메트릭 수집 확인
- [ ] ✅ 대시보드 데이터 표시 확인

> **⚠️ 실패 시**: SSO 로그인 루프 → Grafana `root_url` 설정이 Teleport URL과 일치하는지 확인. Cookie SameSite 문제일 수 있음.

---

## 5. Harbor 초기화

### 5.1 Admin 접근

Harbor UI: Teleport → Harbor → `admin` / `Harbor12345` (기본값) → **즉시 변경**

### 5.2 필수 설정

- [ ] **Admin 비밀번호 즉시 변경**
- [ ] 프로젝트 생성:
  - `library` — 내부 이미지 저장
  - `proxy-dockerhub` — DockerHub 프록시 캐시
  - `proxy-ghcr` — GitHub Container Registry 프록시 캐시
- [ ] Robot Account 생성 (CI/CD 파이프라인용)
- [ ] 취약점 스캔 활성화 (Trivy)

### 5.3 Keycloak SSO 연동

Harbor → Administration → Configuration → Authentication:
- Auth Mode: `OIDC`
- OIDC Endpoint: `https://keycloak.<domain>/realms/platform`
- OIDC Client ID: `harbor`
- OIDC Client Secret: Vault에서 조회 (`vault kv get secret/platform/oidc`)
- OIDC Scope: `openid,profile,email`
- OIDC Auto Onboard: `true`
- OIDC Admin Groups: `admins`

### 5.4 검증

- [ ] ✅ SSO 로그인 성공
- [ ] ✅ 이미지 push/pull 테스트
- [ ] ✅ 프록시 캐시 프로젝트에서 이미지 pull 확인

> **⚠️ 실패 시**: OIDC 연동 실패 → Harbor 로그에서 OIDC discovery 에러 확인. 내부 DNS 해석 문제일 가능성 높음.

---

## 6. Rancher 초기화

### 6.1 Admin 접근

Rancher UI: Teleport → Rancher → `admin` / Quick Reference 테이블 비밀번호  
첫 로그인 시 **비밀번호 변경 강제** (Rancher 기본 동작)

### 6.2 필수 설정

- [ ] RKE2 클러스터 Import:
  1. Cluster Management → Import Existing → Generic
  2. 표시된 `kubectl apply` 명령어 실행
  3. 클러스터 상태 `Active` 확인
- [ ] Server URL 설정 확인

### 6.3 검증

- [ ] ✅ 클러스터 상태 `Active`
- [ ] ✅ Node 목록 정상 표시

> **⚠️ 실패 시**: 클러스터 Import 실패 → `cattle-cluster-agent` Pod 로그 확인. Server URL이 Rancher에 접근 가능한 내부 주소인지 확인.

---

## 7. AIPP 서비스 초기화

### 7.1 서비스 상태 확인

```bash
kubectl get pods -n aipp
# 전체 7개 Pod Running 확인:
#   enai-backend, enai-front, enai-data-processor,
#   enai-scheduler, pgvector-0, rabbitmq-0, redis-0
```

### 7.2 Admin 계정

- 기본 계정: `admin@en-core.com` / `Admin1234!`
- [ ] 비밀번호 즉시 변경

### 7.3 검증

- [ ] ✅ 로그인 성공
- [ ] ✅ 대시보드 정상 표시

> **⚠️ 실패 시**: 로그인 실패 → Backend Pod 로그에서 DB 연결 확인. pgvector Pod가 Ready 상태인지 선행 확인.

---

## 8. 보안 강화 체크리스트

모든 서비스 초기화 완료 후 반드시 수행:

- [ ] 모든 서비스 기본 비밀번호 변경 완료 확인
- [ ] Vault Root Token 안전한 곳에 보관 (운영 시에는 제한된 토큰 사용)
- [ ] Keycloak Admin Secret 삭제: `kubectl delete secret keycloak-admin-secret -n keycloak`
- [ ] ArgoCD initial admin secret 삭제: `kubectl delete secret argocd-initial-admin-secret -n argocd`
- [ ] Git 히스토리에 비밀번호 커밋 여부 점검
- [ ] Teleport MFA 활성화 확인

### Secret Rotation 정책

> **글로벌 표준 (NIST 800-63B)**: 초기 자격증명은 제한된 수명을 가져야 합니다.

| 대상 | 권장 Rotation 주기 | 방법 |
|------|:------------------:|------|
| Vault Root Token | 초기화 후 즉시 revoke | `vault token revoke` → 제한된 정책 토큰 사용 |
| Keycloak Admin PW | 최초 1회 변경 후 비활성화 | Keycloak SSO 계정으로 전환 |
| DB 비밀번호 | 90일 | Vault Dynamic Secrets (향후) |
| OIDC Client Secret | 180일 | Keycloak에서 재생성 → Vault 업데이트 |

---

## 9. Smoke Test

> **글로벌 표준 (Google SRE)**: 배포 후 자동화된 헬스체크로 전체 서비스 정상 상태를 확인합니다.

전체 초기화 완료 후 아래 스크립트로 일괄 검증:

```bash
echo "=== Platform Smoke Test ==="

# 1. K8s 클러스터
echo -n "K8s API Server: "
kubectl cluster-info &>/dev/null && echo "✅" || echo "❌"

# 2. 핵심 Pod 상태
for ns in vault keycloak argocd monitoring harbor cattle-system aipp; do
  NOT_READY=$(kubectl get pods -n $ns --no-headers 2>/dev/null | grep -v Running | grep -v Completed | wc -l)
  echo -n "$ns: "
  [ "$NOT_READY" -eq 0 ] && echo "✅ All Running" || echo "❌ $NOT_READY pods not ready"
done

# 3. Ingress 엔드포인트
for svc in argocd grafana harbor rancher; do
  echo -n "$svc ingress: "
  kubectl get ingress -A --no-headers 2>/dev/null | grep -q $svc && echo "✅" || echo "⚠️ not found"
done

echo "=== Smoke Test Complete ==="
```

---

## 10. 운영 확인 매트릭스

전체 초기화 완료 후 최종 점검:

| 서비스 | Admin 확보 | 비밀번호 변경 | SSO 연동 | 정상 동작 | 비고 |
|--------|:---------:|:----------:|:-------:|:-------:|------|
| Vault | ☐ | — | — | ☐ | Root Token revoke 후 제한 토큰 사용 |
| Keycloak | ☐ | ☐ | — (IdP) | ☐ | Temporary PW로 사용자 생성 |
| ArgoCD | ☐ | ☐ | ☐ | ☐ | initial-admin-secret 삭제 |
| Grafana | ☐ | ☐ | ☐ | ☐ | Datasource 3개 연결 확인 |
| Harbor | ☐ | ☐ | ☐ | ☐ | 프록시 캐시 프로젝트 생성 |
| Rancher | ☐ | ☐ (자동) | — | ☐ | 클러스터 Import 완료 |
| AIPP | ☐ | ☐ | — | ☐ | 7개 Pod Running |

---

## 부록: 문서 이력

| 버전 | 날짜 | 변경 내용 |
|:---:|:---:|:---|
| 1.0 | 2026-02-09 | 초안 작성 |
| 1.5 | 2026-02-10 | Day 1 운영 흐름 재배치 |
| 1.6 | 2026-02-10 | `make opstart` 대시보드 자동화 반영 |
| 2.0 | 2026-02-12 | 전면 개편 — 서비스별 실제 절차 중심 재작성 |
| **2.1** | **2026-02-12** | **글로벌 표준 개선** — Quick Reference 테이블, First-Login Force Change, Secret Rotation 정책, Smoke Test 스크립트, Rollback 가이드, Vault 중앙 Secret 관리 패턴 적용 |
