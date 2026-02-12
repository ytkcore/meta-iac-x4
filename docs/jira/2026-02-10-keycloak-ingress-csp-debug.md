# Keycloak Admin Console Teleport Ingress 디버깅 (1차)

> **Status**: ✅ 완료 (후속: 2/11 Dynamic Hostname 수정)  
> **Priority**: High  
> **Labels**: `keycloak`, `teleport`, `ingress`, `csp`, `cilium`, `bugfix`  
> **작업 기간**: 2026-02-10  
> **주요 커밋**: `ce1bd13`, `7ad9535`, `029eb85`, `086f5e7`, `b54d577`, `987bfe4`, `001f366`, `c764f20`, `158c611`

---

## 📋 요약

Teleport App Access 경유 Keycloak Admin Console 접근 시 발생하는
"somethingWentWrongDescription" 에러의 1차 트러블슈팅.
Ingress CSP 헤더, CiliumNetworkPolicy L7 경로, Keycloak realm import,
KC_HOSTNAME_ADMIN 등 다수의 설정을 순차적으로 디버깅.

최종적으로 2/11에 Dynamic Hostname 방식으로 완전 해결됨.

---

## 🎯 목표

1. Teleport iframe/CSP 관련 보안 헤더 정리
2. CiliumNetworkPolicy에 /admin L7 경로 허용
3. Keycloak realm import에 Teleport redirect URI 추가
4. KC_HOSTNAME_ADMIN 설정 최적값 탐색

---

## 📂 변경 내역 (커밋 순서)

| 커밋 | 변경 |
|:-----|:-----|
| `ce1bd13` | KC_HOSTNAME_ADMIN 추가 — Teleport 경유 Admin Console 접근 수정 |
| `7ad9535` | revert: KC_HOSTNAME_ADMIN 제거 — 어제 작동 설정으로 복원 |
| `029eb85` | Public Ingress에 /admin 경로 추가 — Admin Console SPA API 접근 |
| `086f5e7` | CiliumNetworkPolicy — /admin L7 경로 허용 추가 |
| `b54d577` | Keycloak realm import — Teleport redirect URI 초기화 설정 |
| `987bfe4` | KC_HOSTNAME_ADMIN 추가 — CSP frame-src 오류 해결 |
| `001f366` | Ingress CSP 헤더 재설정 — Teleport iframe 허용 |
| `c764f20` | Ingress — proxy_hide_header 추가 (보안 헤더 재작성 강제) |
| `158c611` | Ingress — X-Frame-Options 헤더 제거 (Deprecated) |

---

## 🔍 디버깅 과정

```
ce1bd13  KC_HOSTNAME_ADMIN 추가
  ↓ (문제 지속)
7ad9535  revert → 어제 설정 복원
  ↓ (다른 원인 탐색)
029eb85  Public Ingress /admin 경로 추가
086f5e7  CiliumNetworkPolicy /admin L7 허용
  ↓ (realm import 확인)
b54d577  Keycloak realm import — redirectUris/webOrigins 설정
987bfe4  KC_HOSTNAME_ADMIN 재추가
  ↓ (CSP 헤더 차단 확인)
001f366  CSP 헤더 재설정 (frame-src/frame-ancestors Teleport 허용)
c764f20  proxy_hide_header로 백엔드 헤더 제거 후 재작성
158c611  X-Frame-Options 제거 (CSP로 대체)
```

> **결론**: 이 1차 디버깅에서는 CSP/iframe 관련 문제는 해결했으나,
> `authServerUrl` cross-domain 문제는 미해결. 2/11에 Dynamic Hostname으로 근본 해결.

---

## ✅ 작업 내역

- [x] **1.1** KC_HOSTNAME_ADMIN 설정/제거 반복 테스트
- [x] **1.2** Public Ingress에 /admin 경로 노출
- [x] **1.3** CiliumNetworkPolicy L7 /admin 경로 허용
- [x] **1.4** Keycloak realm import에 Teleport redirect URI 추가
- [x] **1.5** Ingress CSP 헤더 재설정 (frame-src, frame-ancestors)
- [x] **1.6** proxy_hide_header로 백엔드 보안 헤더 제거
- [x] **1.7** X-Frame-Options 제거 (Deprecated → CSP 대체)

---

## 🔗 관련 티켓

- [keycloak-admin-teleport-proxy-fix](2026-02-11-keycloak-admin-teleport-proxy-fix.md) — **근본 해결** (Dynamic Hostname)
- [keycloak-admin-oidc-https-fix](2026-02-09-keycloak-admin-oidc-https-fix.md) — 전일 OIDC HTTPS 수정
- [teleport-keycloak-rewrite-fix](2026-02-09-teleport-keycloak-rewrite-fix.md) — Teleport rewrite.redirect

---

## 📝 비고

- 이 티켓은 `20260210-keycloak-teleport-access.md`(구형식)를 공식 형식으로 재정리한 것
- 9개 커밋에 걸친 반복적 디버깅 기록 — 복잡한 cross-origin 문제의 층위별 분석 과정
- 최종 근본 원인은 2/11 Dynamic Hostname 티켓에서 확인
