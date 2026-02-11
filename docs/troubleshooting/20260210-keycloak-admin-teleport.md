# [Troubleshooting] Keycloak Admin Console Teleport 접근 오류

## 1. 문제 설명
- **증상**: Teleport Application Access(`https://keycloak-admin.teleport.unifiedmeta.net/admin/master/console/`)를 통해 Keycloak Admin Console에 접근 시, 페이지 로딩에 실패하며 일반적인 "Something went wrong" 에러 화면이 표시됨.
- **환경**: Kubernetes (RKE2), Keycloak v25 (Quarkus), Teleport Application Access, AWS Nginx Ingress Controller.
- **초기 관찰**: 직접 접근 주소(`https://keycloak.dev.unifiedmeta.net/admin/`)는 정상 동작하지만, Teleport 프록시를 경유한 접근만 실패함.

## 2. 근본 원인 분석
브라우저 콘솔 로그 분석 결과, 세 가지 계층의 접근 제어 실패가 확인됨:

### A. OIDC Redirect URI 불일치 (초기 실패)
- **에러**: Keycloak이 Teleport로부터의 인증 요청을 거부함.
- **원인**: `security-admin-console` 클라이언트에 Teleport 프록시 URL이 유효한 redirect URI로 등록되지 않음.
- **해결**: `https://keycloak-admin.teleport.unifiedmeta.net/admin/master/console/*`를 Valid Redirect URIs와 Web Origins에 추가.

### B. CSP (Content Security Policy) 위반
- **에러**: `Refused to display 'https://keycloak.dev.unifiedmeta.net/' in a frame because it violates the following Content Security Policy directive: "frame-src 'self'"`
- **원인**: Keycloak Admin Console은 Teleport 웹 UI 내부의 iframe에서 실행됨. Keycloak의 기본 CSP(`frame-src 'self'`)가 이 교차 출처(cross-origin) 프레이밍을 차단함.
- **해결 시도**: `KC_HOSTNAME_ADMIN`을 설정하여 Keycloak에게 관리자 URL을 알렸으나, 엄격한 헤더가 여전히 유지됨.

### C. X-Frame-Options 차단 (결정적 요인)
- **에러**: `Refused to display ... because it set 'X-Frame-Options' to 'sameorigin'.`
- **원인**: Ingress를 통해 CSP를 완화했음에도 불구하고, Keycloak 백엔드가 계속해서 `X-Frame-Options: SAMEORIGIN` 헤더를 전송함. 브라우저는 허용적인 CSP 설정보다 이 엄격한 헤더를 우선시(혹은 둘 다 적용)하여 차단함. Nginx Ingress의 `more_set_headers`만으로는 백엔드 헤더와의 충돌로 인해 효과적으로 덮어쓰지 못함.

## 3. 해결 조치

### 1단계: Keycloak 설정
Keycloak이 Teleport 엔드포인트와 일치하는 관리자 URL을 생성하도록 설정.
- **파일**: `gitops-apps/keycloak-ingress/keycloak-deployment.yaml`
- **변경**: `KC_HOSTNAME_ADMIN` 환경변수 추가.
  ```yaml
  - name: KC_HOSTNAME_ADMIN
    value: "https://keycloak-admin.teleport.unifiedmeta.net"
  ```

### 2단계: Nginx Ingress 설정 (핵심 수정)
Ingress Controller에서 백엔드 애플리케이션이 보낸 엄격한 헤더를 제거해야 함.
- **파일**: `gitops-apps/keycloak-ingress/resources.yaml`
- **변경**: `proxy_hide_header`를 사용하여 백엔드 보안 헤더를 제거하고, Teleport를 허용하는 완화된 헤더를 주입.
  ```nginx
  nginx.ingress.kubernetes.io/configuration-snippet: |
    # 1. Keycloak 백엔드의 엄격한 헤더 제거
    proxy_hide_header X-Frame-Options;
    proxy_hide_header Content-Security-Policy;
    
    # 2. Teleport 도메인을 허용하는 완화된 CSP 주입
    more_set_headers "Content-Security-Policy: frame-src 'self' https://keycloak-admin.teleport.unifiedmeta.net; frame-ancestors 'self' https://keycloak-admin.teleport.unifiedmeta.net; ...";
    
    # 3. X-Frame-Options는 전송하지 않음 (CSP frame-ancestors에 의존)
    # more_set_headers "X-Frame-Options: ..."  <-- 브라우저 호환성 문제 방지를 위해 제거
  ```

## 4. 검증
- **브라우저**: Teleport URL로 접속 시 Keycloak Admin Console이 성공적으로 로드됨.
- **헤더**:
    - `X-Frame-Options`: **제거됨** (Hidden).
    - `Content-Security-Policy`: `frame-ancestors ... keycloak-admin.teleport.unifiedmeta.net` 포함 확인.
- **로그인 동작 확인 (중요)**:
    - 초기 접속 시, 인증을 위해 `keycloak.dev.unifiedmeta.net` (IdP)로 **리다이렉트**되는 현상은 **정상 동작**입니다.
    - 로그인 성공 후 다시 Teleport URL(`keycloak-admin.teleport...`)로 자동 복귀합니다.
