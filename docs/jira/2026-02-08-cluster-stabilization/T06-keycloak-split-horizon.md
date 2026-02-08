# T6: Keycloak Split-Horizon 적용

> **Parent**: [클러스터 안정화](../2026-02-08-cluster-stabilization.md) | **Status**: ✅ 완료

## 📋 Summary

Keycloak을 단일 도메인(`keycloak.dev.unifiedmeta.net`)에서 **Split-Horizon Ingress** 패턴으로 분리: Public(인증 API) + Internal(Admin Console). Public에서 `/admin` 경로 접근을 완전 차단.

## 🏗️ Architecture

```
                    ┌──────────────────────────────────────────┐
                    │        keycloak.dev.unifiedmeta.net       │
                    ├─────────────────┬────────────────────────┤
                    │   Public NLB    │    Internal NLB        │
                    │   (nginx)       │    (nginx-internal)    │
                    ├─────────────────┼────────────────────────┤
                    │ /realms/*       │ /admin/*               │
                    │ /resources/*    │ /admin/realms/*        │
                    │ /js/*           │                        │
                    │ /robots.txt     │                        │
                    ├─────────────────┴────────────────────────┤
                    │         K8s Service → Keycloak EC2       │
                    │              10.0.101.201:8080            │
                    └──────────────────────────────────────────┘
```

## 🔧 구현

### Public Ingress (`keycloak-public`)
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak-public
  namespace: keycloak
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    # WAF 설정은 T8에서 추가
spec:
  ingressClassName: nginx          # Public NLB
  rules:
    - host: keycloak.dev.unifiedmeta.net
      http:
        paths:
          - path: /realms          # OIDC/SAML 인증
            pathType: Prefix
          - path: /resources       # 로그인 정적 리소스
            pathType: Prefix
          - path: /js              # JS 어댑터
            pathType: Prefix
          - path: /robots.txt      # SEO
            pathType: Exact
```

### Internal Ingress (`keycloak-admin`)
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak-admin
  namespace: keycloak
spec:
  ingressClassName: nginx-internal  # Internal NLB
  rules:
    - host: keycloak.dev.unifiedmeta.net
      http:
        paths:
          - path: /admin           # Admin Console
            pathType: Prefix
          - path: /admin/realms    # Admin REST API
            pathType: Prefix
```

## 💡 설계 원칙

Split-Horizon의 핵심: **동일 도메인, 경로 기반 분리**

| 이유 | 설명 |
|------|------|
| OIDC Discovery | `/.well-known/openid-configuration`이 도메인 기반 → 도메인 분리 불가 |
| AWS IAM OIDC | OIDC Provider가 Public에서 Discovery endpoint 접근 필요 |
| Admin 보안 | Admin Console은 절대 Public 노출 불가 |

## ✅ 검증

| Ingress | Class | 경로 | 접근 |
|---------|-------|------|------|
| `keycloak-public` | `nginx` (Public) | `/realms`, `/resources`, `/js` | ✅ 외부 접근 가능 |
| `keycloak-admin` | `nginx-internal` (Internal) | `/admin` | ✅ VPN/Teleport 전용 |

Public NLB에서 `/admin` 접근 시 → **404 Not Found** (Ingress 규칙 미매칭)

## 🔧 변경 파일

| 파일 | 변경 | 커밋 |
|------|------|------|
| `gitops-apps/keycloak-ingress/resources.yaml` | Split-Horizon Ingress 구성 | `893a212` |

## 🏷️ Labels
`keycloak`, `ingress`, `split-horizon`, `security`
