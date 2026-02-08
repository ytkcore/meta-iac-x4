# T8: Keycloak WAF-Equivalent Protection

> **Parent**: [클러스터 안정화](../2026-02-08-cluster-stabilization.md) | **Status**: ✅ 완료

## 📋 Summary

AWS WAF는 NLB를 직접 지원하지 않음 → nginx Ingress annotations + CiliumNetworkPolicy L7으로 동등 수준의 WAF 보호를 구현.

## 🔍 문제

AWS WAF → ALB 전용. 현 아키텍처는 **NLB → nginx-ingress** 구조이므로 WAF 직접 적용 불가.
Keycloak 인증 API가 Public NLB에 노출되어 있어 brute-force, DDoS 등의 공격에 취약.

## 🏗️ 3-Layer WAF Architecture

```
┌──────────────────────────────────────────────────┐
│             3-Layer WAF Protection                │
├──────────────────────────────────────────────────┤
│ Layer 1: nginx Rate Limiting                      │
│   · 20 rps / 300 rpm / burst ×5 / 10 conn       │
│   · Request body max 1MB                          │
├──────────────────────────────────────────────────┤
│ Layer 2: Security Headers                         │
│   · X-Content-Type-Options: nosniff              │
│   · X-Frame-Options: SAMEORIGIN                  │
│   · X-XSS-Protection: 1; mode=block             │
│   · Referrer-Policy: strict-origin               │
│   · Permissions-Policy: camera=(), mic=(), geo=()│
├──────────────────────────────────────────────────┤
│ Layer 3: CiliumNetworkPolicy L7                   │
│   · Public → /realms, /resources, /js만 허용      │
│   · Internal → 모든 경로 허용                     │
│   · /admin 경로 → L7 레벨 차단                    │
└──────────────────────────────────────────────────┘
```

## 🔧 구현

### Layer 1: nginx Rate Limiting
```yaml
# keycloak-public Ingress annotations
nginx.ingress.kubernetes.io/limit-rps: "20"
nginx.ingress.kubernetes.io/limit-rpm: "300"
nginx.ingress.kubernetes.io/limit-burst-multiplier: "5"
nginx.ingress.kubernetes.io/limit-connections: "10"
nginx.ingress.kubernetes.io/proxy-body-size: "1m"
```

### Layer 2: Security Headers
```yaml
nginx.ingress.kubernetes.io/configuration-snippet: |
  more_set_headers "X-Content-Type-Options: nosniff";
  more_set_headers "X-Frame-Options: SAMEORIGIN";
  more_set_headers "X-XSS-Protection: 1; mode=block";
  more_set_headers "Referrer-Policy: strict-origin-when-cross-origin";
  more_set_headers "Permissions-Policy: camera=(), microphone=(), geolocation=()";
```

### Layer 3: CiliumNetworkPolicy L7
```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: keycloak-l7-protection
  namespace: keycloak
spec:
  endpointSelector:
    matchLabels:
      app: keycloak
  ingress:
    # Internal → 모든 경로 허용
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/instance: nginx-ingress-internal
      toPorts:
        - ports:
            - port: "8080"
    # Public → 인증 경로만 허용
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/instance: nginx-ingress
      toPorts:
        - ports:
            - port: "8080"
          rules:
            http:
              - method: "GET"
                path: "/realms/.*"
              - method: "POST"
                path: "/realms/.*"
              - method: "GET"
                path: "/resources/.*"
              - method: "GET"
                path: "/js/.*"
              - method: "GET"
                path: "/robots.txt"
```

## 💡 AWS WAF vs nginx+Cilium 비교

| 기능 | AWS WAF | nginx + Cilium 조합 |
|------|---------|---------------------|
| Rate Limiting | ✅ | ✅ nginx annotation |
| IP 차단 | ✅ (IP Set) | ⚠️ CiliumNetworkPolicy L3 |
| SQL Injection | ✅ (Managed Rules) | ❌ 미대응 |
| XSS | ✅ (Managed Rules) | ⚠️ Headers만 |
| Path Filtering | ✅ | ✅ CiliumNetworkPolicy L7 |
| Geo-blocking | ✅ | ❌ |
| 비용 | $5/ACL + 요청당 | 무료 |

> 현 단계에서 SQL Injection/XSS mangaged rules 부재는 Keycloak 자체 보안으로 대체 가능. ALB 전환 시 AWS WAF 적용 예정.

## 🔧 변경 파일

| 파일 | 변경 | 커밋 |
|------|------|------|
| `gitops-apps/keycloak-ingress/resources.yaml` | Rate Limit + Headers + L7 Policy | `7221364` |

## 🏷️ Labels
`waf`, `security`, `keycloak`, `cilium`, `nginx`, `rate-limit`
