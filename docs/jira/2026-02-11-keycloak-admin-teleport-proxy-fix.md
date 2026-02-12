# Keycloak Admin Console Teleport 프록시 접근 수정 (Dynamic Hostname)

> **Status**: ✅ 완료  
> **Priority**: High  
> **Labels**: `keycloak`, `teleport`, `app-access`, `oidc`, `bugfix`  
> **작업 기간**: 2026-02-11  
> **주요 커밋**: `465ca07`, `a082237`, `aa304af`

---

## 📋 요약

Teleport App Access 경유 Keycloak Admin Console 접근 시 `somethingWentWrongDescription` 에러 재발.
근본 원인은 **Teleport App Access가 브라우저의 모든 HTTP 요청을 프록시**하여,
Admin SPA가 `authServerUrl`(= `KC_HOSTNAME`)로 cross-domain API 호출 시 **타임아웃** 발생.
`KC_HOSTNAME`/`KC_HOSTNAME_ADMIN`을 모두 제거하고 **동적 호스트 감지 모드**로 전환하여 해결.

---

## 🎯 목표

1. Keycloak Admin Console의 Teleport 접근 정상화
2. OIDC issuer `https://` 유지 확인 (SSO 클라이언트 호환)
3. 이전 수정(`2026-02-09`)과의 차이점 문서화

---

## 📂 변경 파일

| 파일 | 변경 |
|:-----|:-----|
| `gitops-apps/keycloak-ingress/keycloak-deployment.yaml` | `KC_HOSTNAME`, `KC_HOSTNAME_ADMIN` 제거 + `KC_HOSTNAME_STRICT_BACKCHANNEL=false` 추가 |

---

## 🔍 진단 과정

### Phase 1: 기존 설정 분석

- [x] **1.1** 이전 Jira(`2026-02-09-keycloak-admin-oidc-https-fix`) 참조
  - 당시 수정: `KC_HOSTNAME=https://keycloak.dev.unifiedmeta.net` (OIDC issuer https 보장)
  - `KC_HOSTNAME_ADMIN=https://keycloak-admin.teleport.unifiedmeta.net`
- [x] **1.2** 동일 설정이지만 `somethingWentWrongDescription` 재발 확인
- [x] **1.3** 이전 Jira(`2026-02-09-teleport-keycloak-rewrite-fix`) 참조
  - `rewrite.redirect` 설정 확인 (Location header rewrite만 수행)

### Phase 2: 3가지 설정 조합 테스트

```
┌──────────────────────────────┬────────────────────────────────────────┐
│ 설정                         │ 결과                                   │
├──────────────────────────────┼────────────────────────────────────────┤
│ KC_HOSTNAME ✅               │ somethingWentWrongDescription          │
│ KC_HOSTNAME_ADMIN ✅         │ (authServerUrl → 외부 도메인 타임아웃) │
├──────────────────────────────┼────────────────────────────────────────┤
│ KC_HOSTNAME ✅               │ Loading the Administration Console     │
│ KC_HOSTNAME_ADMIN ❌         │ (authServerUrl → 외부 도메인 접근 불가)│
├──────────────────────────────┼────────────────────────────────────────┤
│ KC_HOSTNAME ❌               │ ✅ 정상 (로그인 페이지 + 대시보드)    │
│ KC_HOSTNAME_ADMIN ❌         │ (authServerUrl → Teleport 프록시 내)  │
└──────────────────────────────┴────────────────────────────────────────┘
```

### Phase 3: 브라우저 직접 디버깅 (핵심)

- [x] **3.1** SSM OIDC Discovery 확인 — `issuer: https://...` ✅, CORS ✅
- [x] **3.2** SSM Admin SPA config 확인 — `authServerUrl: keycloak.dev.~`, `authUrl: keycloak-admin.teleport.~`
- [x] **3.3** Public DNS 확인 — `dig @8.8.8.8` → resolve 정상 (NLB IP)
- [x] **3.4** **브라우저에서 `fetch("https://keycloak.dev.unifiedmeta.net/...")` → 타임아웃**
  - 3p-cookies iframe → status 0
  - **Teleport App Access이 브라우저의 외부 도메인 요청을 차단**

### Phase 4: 해결

- [x] **4.1** `KC_HOSTNAME`/`KC_HOSTNAME_ADMIN` 모두 제거
- [x] **4.2** `KC_PROXY_HEADERS=xforwarded` (기존 유지) + `KC_HOSTNAME_STRICT=false`
- [x] **4.3** `KC_HOSTNAME_STRICT_BACKCHANNEL=false` 추가
- [x] **4.4** ArgoCD 싱크 → Keycloak pod 재시작 → 정상 확인

---

## 🔑 핵심 해결 사항

### Teleport App Access의 프록시 구조

```
Browser ─── Teleport Proxy ─── Internal NLB ─── Nginx ─── Keycloak Pod

Teleport은 브라우저의 모든 HTTP 요청을 프록시함
→ SPA가 Teleport 밖의 도메인으로 fetch() → 타임아웃
→ KC_HOSTNAME 설정 시 authServerUrl이 외부 도메인 → 실패
```

### 동적 호스트 감지 모드

```diff
# keycloak-deployment.yaml
  KC_PROXY_HEADERS=xforwarded
- KC_HOSTNAME=https://keycloak.dev.unifiedmeta.net
- KC_HOSTNAME_ADMIN=https://keycloak-admin.teleport.unifiedmeta.net
+ # KC_HOSTNAME 미설정 → X-Forwarded-Host에서 동적 감지
+ KC_HOSTNAME_STRICT=false
+ KC_HOSTNAME_STRICT_BACKCHANNEL=false
```

> **원리**: `KC_HOSTNAME`이 없으면 Keycloak은 `X-Forwarded-Host` 헤더에서 hostname을 동적으로 감지.
> Nginx Ingress의 `proxy_set_header X-Forwarded-Proto https;` 덕분에 scheme도 https 유지.

| 접근 경로 | X-Forwarded-Host | authServerUrl | issuer |
|:----------|:-----------------|:--------------|:-------|
| Teleport 경유 | `keycloak-admin.teleport.~` | `https://keycloak-admin.teleport.~` | `https://keycloak-admin.teleport.~` |
| Public 직접 | `keycloak.dev.~` | `https://keycloak.dev.~` | `https://keycloak.dev.~` |

### 이전 수정(`02-09`)과의 차이

| 항목 | 2026-02-09 | 2026-02-11 |
|:-----|:-----------|:-----------|
| 근본 원인 | OIDC issuer `http://` 반환 | Teleport 프록시 외부 도메인 타임아웃 |
| 해결 | `KC_HOSTNAME=https://...` 설정 | `KC_HOSTNAME` 제거 → 동적 감지 |
| 왜 변경 | OIDC issuer에 scheme 명시 필요 | Teleport 프록시에서 외부 fetch 차단 |

> **2/9 수정이 2/11에 문제된 이유**: Teleport App Access 환경에서
> 브라우저가 `keycloak.dev.unifiedmeta.net`에 직접 접근할 수 없음을 발견.
> 당시에는 정상이었으나, Teleport 프록시 고도화 또는 브라우저 접근 환경 변경으로 재발.

---

## ⚠️ 후속 과제

- [ ] OIDC issuer 동적 감지 시 SSO 클라이언트(Grafana, Vault 등) 호환성 확인
  - issuer가 접근 경로에 따라 달라지므로, SSO 클라이언트가 기대하는 issuer와 일치하는지 검증 필요
  - `curl https://keycloak.dev.unifiedmeta.net/realms/master/.well-known/openid-configuration`
- [ ] Teleport App Access에서 `rewrite.headers` 활용 가능성 검토
  - admin SPA의 외부 요청을 Teleport 내부로 라우팅하는 대안

---

## 🔗 관련 티켓

- [keycloak-admin-oidc-https-fix](2026-02-09-keycloak-admin-oidc-https-fix.md) — OIDC HTTPS issuer 수정 (이전 세션)
- [teleport-keycloak-rewrite-fix](2026-02-09-teleport-keycloak-rewrite-fix.md) — Teleport rewrite.redirect 설정
- [keycloak-k8s-native-deployment](2026-02-09-keycloak-k8s-native-deployment.md) — K8s 네이티브 전환

---

## 📌 Priority / Status

**High** | ✅ **Done**
