# Harbor OIDC 연동 가이드 (Keycloak SSO)

> **상태**: 📋 Post-Deploy  
> **선행조건**: Keycloak 정상 운영, Harbor 정상 운영, Teleport 접근 가능

---

## Step 1: Keycloak — Harbor 클라이언트 생성

Teleport 경유로 Keycloak Admin Console 접속:

```bash
# Teleport App Access 경유
tsh apps login keycloak-admin
# 또는 브라우저에서: https://keycloak-admin.teleport.dev.unifiedmeta.net
```

### 1.1 클라이언트 생성

1. **Realm 선택**: `platform` (드롭다운)
2. **Clients → Create client**
3. 설정:

| 항목 | 값 |
|:-----|:---|
| Client type | OpenID Connect |
| Client ID | `harbor` |
| Name | Harbor OCI Registry |
| Client authentication | **ON** |
| Authorization | OFF |

4. **Save**

### 1.2 설정 탭 (Settings)

| 항목 | 값 |
|:-----|:---|
| Root URL | `https://harbor.unifiedmeta.net` |
| Home URL | `https://harbor.unifiedmeta.net` |
| Valid redirect URIs | `https://harbor.unifiedmeta.net/c/oidc/callback` |
| Valid post logout redirect URIs | `https://harbor.unifiedmeta.net` |
| Web origins | `https://harbor.unifiedmeta.net` |

5. **Save**

### 1.3 Client Secret 복사

1. **Credentials** 탭 이동
2. **Client secret** 값 복사 → 📋 메모

### 1.4 Client Scope 확인

기본 `openid`, `profile`, `email` 스코프가 할당되어 있는지 확인.
**groups** 스코프가 없으면:

1. **Client scopes** → `platform-dedicated` 선택
2. **Add mapper** → By configuration → **Group Membership**
3. Name: `groups`, Token Claim Name: `groups`, Full group path: **OFF**

---

## Step 2: Harbor — OIDC 인증 설정

Teleport 경유로 Harbor Admin UI 접속:

```bash
tsh apps login harbor
# 또는 브라우저에서: https://harbor.teleport.dev.unifiedmeta.net
```

1. **Administration → Configuration → Authentication**
2. **Auth Mode**: `OIDC`
3. 설정:

| 항목 | 값 |
|:-----|:---|
| OIDC Provider Name | `Keycloak` |
| OIDC Endpoint | `https://keycloak.dev.unifiedmeta.net/realms/platform` |
| OIDC Client ID | `harbor` |
| OIDC Client Secret | *(Step 1.3에서 복사한 값)* |
| Group Claim Name | `groups` |
| OIDC Scope | `openid,profile,email,groups` |
| Verify Certificate | ✅ (체크 해제 if self-signed) |
| Automatic Onboarding | ✅ |
| Username Claim | `preferred_username` |

4. **Save** → **Test OIDC Server**

---

## Step 3: 검증

1. Harbor 로그아웃
2. 로그인 페이지에서 **LOGIN VIA OIDC PROVIDER** 클릭
3. Keycloak 로그인 페이지로 redirect 확인
4. 로그인 후 Harbor 대시보드 접근 확인

---

## 트러블슈팅

| 증상 | 원인 | 해결 |
|:-----|:-----|:-----|
| OIDC callback 404 | Redirect URI 불일치 | Keycloak Valid redirect URIs 확인 |
| SSL 에러 | 인증서 검증 실패 | Harbor에서 Verify Certificate 해제 |
| 그룹 미표시 | groups claim 없음 | Keycloak Group Membership mapper 추가 |
| issuer 불일치 | HTTP/HTTPS 차이 | `KC_HOSTNAME=https://...` 확인 |
