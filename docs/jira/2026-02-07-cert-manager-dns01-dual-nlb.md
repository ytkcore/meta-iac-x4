# [INFRA] cert-manager DNS-01 전환 + Dual NLB (Internal NLB) 구축

## 📋 Summary

cert-manager의 HTTP-01 challenge에서 발생하는 **헤어핀 라우팅 문제**를 DNS-01 challenge로 전환하여 해결하고,
VPC 내부 트래픽을 위한 **Internal NLB + nginx-ingress-internal** 구성으로 Dual NLB 아키텍처를 구축한다.

## 🎯 Goals

1. **DNS-01 Challenge**: Private VPC에서도 인증서 자동 발급/갱신 가능
2. **Internal NLB**: Teleport/내부 서비스 → Private NLB 경유 접근
3. **Dual NLB 아키텍처**: Public NLB(외부) + Internal NLB(VPC 내부)
4. **Route53 IAM**: `route53:GetChange` 권한 추가로 DNS propagation 확인

## 📊 문제 원인 — HTTP-01 Hairpin

```
cert-manager → ACME HTTP-01 challenge
  → Let's Encrypt가 *.unifiedmeta.net에 HTTP 요청
    → Public NLB → nginx → cert-manager solver Pod ✅ (외부)

cert-manager 자체 DNS propagation check
  → Route53 Public Zone 쿼리 시도
    → VPC 내부에서 Public NLB IP로 resolve
      → Hairpin 라우팅 — 도달 불가 ❌
```

**해결**: DNS-01 challenge + Route53 TXT 레코드 기반 검증

## 📋 Tasks (완료)

### cert-manager DNS-01
- [x] ClusterIssuer를 HTTP-01 → DNS-01로 전환
- [x] Route53 IAM 권한 추가 (`route53:GetChange`)
- [x] `--dns01-recursive-nameservers=8.8.8.8:53` 설정 (재귀 DNS)
- [x] 인증서 자동 발급 검증 (argocd, rancher, grafana 등)

### Internal NLB + Dual NLB
- [x] `nginx-ingress-internal.yaml` — Internal NLB용 nginx-ingress 배포
- [x] Internal NLB 자동 생성 확인 (CCM)
- [x] Worker Node를 Internal NLB Target Group에 수동 등록
- [x] Private Zone DNS → Internal NLB 전환
- [x] Teleport EC2 → Internal NLB 경유 서비스 접근 검증

### 문서화
- [x] RKE2 Private VPC TLS Setup Guide 작성
- [x] Route53 GetChange IAM 권한 트러블슈팅 문서

## 📊 Dual NLB 최종 구조

```
외부 사용자 → Public NLB → nginx-ingress (Public)
                                    ↓
                              Ingress → Pod

Teleport EC2 → Internal NLB → nginx-ingress (Internal)
내부 워크로드              ↓
                    Ingress → Pod (동일 Ingress 공유)
```

## 🔧 주요 변경 파일

| 파일 | 작업 |
|------|------|
| `gitops-apps/bootstrap/cert-manager.yaml` | ✏️ DNS-01 solver 설정 |
| `gitops-apps/bootstrap/nginx-ingress-internal.yaml` | 🆕 Internal nginx-ingress |
| `stacks/dev/50-rke2/main.tf` | ✏️ Route53 IAM 권한 추가 |
| `docs/troubleshooting/cert-manager-http01-hairpin-issue.md` | 🆕 트러블슈팅 |
| `docs/troubleshooting/rke2-private-vpc-tls-setup-guide.md` | 🆕 가이드 |

## ⚠️ 알려진 제약

- Internal NLB Target Group은 CCM 버그로 수동 등록 필요
- Cilium 전환(Phase 6) 후 ALBC IP-mode로 자동 관리 예정

## 📎 References

- [cert-manager DNS-01 트러블슈팅](../troubleshooting/cert-manager-http01-hairpin-issue.md)
- [RKE2 Private VPC TLS Guide](../troubleshooting/rke2-private-vpc-tls-setup-guide.md)
- [Teleport App Access 트러블슈팅](../troubleshooting/teleport-app-access-internal-nlb.md)

## 🏷️ Labels

`cert-manager`, `dns-01`, `internal-nlb`, `dual-nlb`, `tls`

## 📌 Priority / Status

**High** / ✅ 완료 (2026-02-07)
