# [INFRA] TLS 체계 전환 — cert-manager + Let's Encrypt 통합

## 📋 Summary

RKE2 클러스터의 TLS 인증서 관리를 **cert-manager + Let's Encrypt**로 일원화한다.
기존 Rancher의 TLS 리다이렉트 루프, nginx-ingress proxy protocol 이슈를 해결하고,
모든 서비스에 자동 인증서 발급/갱신 체계를 구축한다.

## 🎯 Goals

1. cert-manager ClusterIssuer를 통한 Let's Encrypt 자동 발급
2. Rancher TLS 리다이렉트 루프 해결
3. nginx-ingress NLB 연동 안정화
4. 모든 서비스(ArgoCD, Rancher, Grafana 등)에 HTTPS 적용

## 📊 해결한 문제 체인

```
Rancher TLS 활성화 → 302 리다이렉트 루프 발생
  → ssl-redirect 비활성화 시도 → 여전히 루프
    → 원인: NLB → nginx 구간에서 x-forwarded-proto 미전달
      → proxy protocol 활성화 시도 → NLB + nginx 양쪽 설정 필요
        → 최종 해결: tls: external 모드 + snippet annotation으로 헤더 강제 주입
```

## 📋 Tasks (완료)

- [x] cert-manager ClusterIssuer 생성 (Let's Encrypt staging/production)
- [x] Rancher TLS 활성화 (`cert-manager.io/cluster-issuer` annotation)
- [x] nginx-ingress snippet annotation 허용 (`allow-snippet-annotations: true`)
- [x] proxy protocol 설정 최적화 (NLB bypass 모드 채택)
- [x] `x-forwarded-proto: https` 강제 주입으로 리다이렉트 루프 해결
- [x] 전체 서비스 HTTPS 접근 확인

## ⚠️ 트러블슈팅 이력

| 시도 | 결과 | 교훈 |
|------|------|------|
| `tls: ingress` 모드 | 리다이렉트 루프 | Rancher가 자체 TLS termination 시도 시 충돌 |
| `ssl-redirect: false` | 여전히 루프 | Rancher 내부 로직이 X-Forwarded-Proto 검사 |
| proxy protocol 활성화 | 일시 해결 | NLB↔nginx 양쪽 동시 설정 필수 |
| **`tls: external` + snippet** | ✅ 해결 | TLS termination을 nginx에 위임, 헤더 직접 주입 |

## 📎 References

- [RKE2 Private VPC TLS Setup Guide](../troubleshooting/rke2-private-vpc-tls-setup-guide.md)

## 🏷️ Labels

`tls`, `cert-manager`, `letsencrypt`, `nginx-ingress`

## 📌 Priority / Status

**High** / ✅ 완료 (2026-02-02)
