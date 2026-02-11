# [FIX] Keycloak Admin Console Teleport 접근 불가 수정

- **상태**: 완료 (Done)
- **우선순위**: 높음 (High)
- **담당자**: DevOps 팀
- **라벨**: Keycloak, Teleport, Ingress, Security, Bugfix

## 요약 (Summary)
Teleport Application Access(`https://keycloak-admin.teleport...`)를 통해 Keycloak Admin Console에 접근 시, "Something went wrong" 에러가 발생하며 접근이 불가능했습니다. 이로 인해 Harbor OIDC 클라이언트 설정 등 후속 작업이 차단되었습니다.

## 근본 원인 (Root Cause)
1. **OIDC 불일치**: 초기 설정 시 `security-admin-console` 클라이언트의 `redirect_uri`에 Teleport 프록시 URL이 누락되었습니다.
2. **보안 헤더 차단**: Keycloak의 기본 보안 헤더(`X-Frame-Options: SAMEORIGIN` 및 `frame-src 'self'`)가 Teleport의 iframe 메커니즘 내에서 애플리케이션 실행을 차단했습니다.

## 해결 방법 (Solution Implemented)
1. **Keycloak 클라이언트 수정**: `security-admin-console` 클라이언트에 Teleport Redirect URI 및 Web Origins를 수동으로 추가했습니다.
2. **호스트네임 설정**: `KC_HOSTNAME_ADMIN` 환경변수를 적용하여 관리자 링크가 Teleport 도메인으로 올바르게 생성되도록 했습니다.
3. **Ingress 헤더 조작**:
    - `proxy_hide_header`를 사용하여 Keycloak 백엔드 응답에서 `X-Frame-Options` 및 `Content-Security-Policy` 헤더를 제거했습니다.
    - `more_set_headers`를 사용하여 Teleport 도메인의 `frame-src` 및 `frame-ancestors`를 허용하는 완화된 `Content-Security-Policy`를 주입했습니다.

## 검증 (Verification)
- **테스트 URL**: `https://keycloak-admin.teleport.unifiedmeta.net/admin/master/console/`
- **결과**: Teleport 내부에서 로그인 페이지가 정상적으로 로드되며, Admin Console 기능이 완전하게 동작합니다.
- **특이사항**: 로그인 시 `keycloak.dev...`로 리다이렉트 후 복귀하는 것은 OIDC 표준 흐름에 따른 **정상 동작**입니다.
- **산출물**: 상세 트러블슈팅 가이드가 `docs/troubleshooting/20260210-keycloak-admin-teleport.md`에 작성되었습니다.
