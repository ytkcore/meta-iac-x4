# Keycloak Admin Console 접근 수정 (OIDC HTTPS + ArgoCD Secret 보호)

> **Status**: ✅ 완료  
> **Priority**: High  
> **Labels**: `keycloak`, `teleport`, `oidc`, `security`, `argocd`  
> **작업 기간**: 2026-02-09  
> **주요 커밋**: `e0fda00`, `94cfd86`, `37a4b21`, `c0a48c9`

---

## 📋 요약

Teleport을 통한 Keycloak Admin Console 접근 시 `somethingWentWrongDescription` 오류 발생.
근본 원인은 **OIDC issuer가 `http://`로 반환**되어 Admin Console SPA의 OIDC 인증 초기화 실패.
DNS, Ingress, Keycloak Hostname, ArgoCD Secret 관리 등 **4개 계층의 문제**를 진단하고 해결.

---

## 🎯 목표

1. Keycloak Admin Console의 Teleport 접근 정상화
2. OIDC Discovery issuer `http://` → `https://` 수정
3. ArgoCD selfHeal에 의한 DB Secret 덮어쓰기 방지
4. 80-access-gateway IaC 동기화 확인

---

## 📂 변경 파일

| 파일 | 변경 |
|:-----|:-----|
| `gitops-apps/keycloak-ingress/keycloak-deployment.yaml` | `KC_HOSTNAME` full URL 설정 + Secret stringData 제거 |
| `gitops-apps/keycloak-ingress/resources.yaml` | DNS annotation 이동 + nginx X-Forwarded-Proto 추가 |
| `stacks/dev/80-access-gateway/variables.tf` | keycloak-admin Teleport 앱 등록 (이전 세션) |

---

## ✅ 작업 내역

### Phase 1: 진단 (2/9 저녁)

- [x] **1.1** Teleport 경유 Keycloak Admin Console `somethingWentWrongDescription` 재현
- [x] **1.2** OIDC Discovery 분석 → `issuer: http://keycloak.dev.unifiedmeta.net:443` 탐지
- [x] **1.3** Admin Console SPA 환경 블록 분석 → `authServerUrl` 확인

### Phase 2: DNS & Ingress 수정

- [x] **2.1** `external-dns` annotation을 Internal → **Public** Ingress로 이동 (`e0fda00`)
  - 브라우저에서 `keycloak.dev.unifiedmeta.net` → Public NLB 접근 가능하게 수정
- [x] **2.2** nginx `configuration-snippet`에 `proxy_set_header X-Forwarded-Proto https` 추가 (`94cfd86`)

### Phase 3: Keycloak Hostname v2 수정 (핵심)

- [x] **3.1** `KC_HOSTNAME=keycloak.dev.unifiedmeta.net` (hostname only, no scheme) 문제 확인
- [x] **3.2** Keycloak v25 Hostname v2 공식 문서 확인: `KC_HOSTNAME`이 full URL 수용
- [x] **3.3** `KC_HOSTNAME=https://keycloak.dev.unifiedmeta.net` 적용 (`37a4b21`)
  - OIDC issuer: `https://keycloak.dev.unifiedmeta.net/realms/master` ✅

### Phase 4: ArgoCD Secret 보호

- [x] **4.1** ArgoCD `selfHeal`이 `stringData: CHANGE_ME`로 DB Secret 덮어쓰기 문제 발견
  - `ignoreDifferences`는 diff만 무시, apply 시 `stringData` → `data` 변환은 차단 불가
- [x] **4.2** `keycloak-db-secret`, `keycloak-admin-secret`의 `stringData` 완전 제거 (`c0a48c9`)
  - Secret 껍데기만 Git에 유지, 실제 값은 수동 설정 (kubectl 커맨드 주석 추가)

### Phase 5: IaC 동기화 확인

- [x] **5.1** `make plan ENV=dev STACK=80-access-gateway` → **No changes** (IaC 정합)

---

## 🔑 핵심 해결 사항

### 1. OIDC Issuer HTTP → HTTPS

```diff
# keycloak-deployment.yaml
- KC_HOSTNAME=keycloak.dev.unifiedmeta.net        # hostname only → http:// 기본
+ KC_HOSTNAME=https://keycloak.dev.unifiedmeta.net # full URL → https:// 명시
```

> Keycloak v25 Hostname v2는 `KC_HOSTNAME`에 scheme 포함 full URL을 권장.
> `KC_HOSTNAME_URL`은 비표준 옵션으로 OIDC API에는 영향 없음.

### 2. ArgoCD Secret 보호 패턴

```diff
# keycloak-deployment.yaml
  kind: Secret
  metadata:
    name: keycloak-db-secret
  type: Opaque
- stringData:
-   KC_DB_USERNAME: "CHANGE_ME"
-   KC_DB_PASSWORD: "CHANGE_ME"
+ # 실제 값은 배포 후 수동 설정 (ArgoCD ignoreDifferences 보호)
```

> `ignoreDifferences: [/data, /stringData]`는 diff 비교 시에만 적용.
> ArgoCD apply 시 `stringData`가 `data`로 변환되어 기존 값을 덮어씀.
> **해결**: `stringData` 자체를 Git에서 제거.

---

## 🔗 관련 티켓

- [keycloak-k8s-migration](2026-02-08-keycloak-k8s-migration.md) — K8s 네이티브 전환
- [teleport-app-service-completion](2026-02-09-teleport-app-service-completion.md) — Teleport App Service 구축
- [teleport-keycloak-rewrite-fix](2026-02-09-teleport-keycloak-rewrite-fix.md) — rewrite_redirect 설정

---

## 📝 비고

- OIDC Discovery `http://` 문제는 SSO 통합(Grafana, Vault 등)에도 영향을 주었을 가능성 있음
- ArgoCD Secret 관리의 근본적 해결은 **External Secrets Operator (ESO)** 도입 필요
  - 현재 Secret Management Strategy Phase 2로 계획됨
- `KC_PROXY_HEADERS=xforwarded`는 유지 — 향후 nginx가 올바른 `X-Forwarded-Proto`를 보내면 추가 보호 역할
