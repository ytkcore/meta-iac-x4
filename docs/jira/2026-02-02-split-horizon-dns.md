# [INFRA] Split-Horizon DNS 구축 — ExternalDNS Dual Zone 분리

## 📋 Summary

동일 도메인(`unifiedmeta.net`)에 대해 Public Zone(NLB DNS)과 Private Zone(Node IP)을 분리하여,
외부 사용자와 내부 워크로드가 각자 최적의 경로로 서비스에 접근하도록 **Split-Horizon DNS**를 구축한다.

## 🎯 Goals

1. Public DNS → NLB → Ingress → Pod (외부 사용자)
2. Private DNS → Node IP → Pod (내부 EC2, Teleport 등)
3. ExternalDNS를 Public/Private 인스턴스로 분리
4. 최소 권한 IAM Policy 적용 (Zone ID 한정)

## 📊 아키텍처

```
외부 사용자 → Route53 Public Zone
  → argocd.unifiedmeta.net → NLB DNS (Public)
  → NLB → nginx-ingress → Pod

Teleport EC2 → Route53 Private Zone
  → argocd.unifiedmeta.net → Worker Node IP (10.0.x.x)
  → Node → kube-proxy → Pod
```

## 📋 Tasks (완료)

- [x] `external-dns-private.yaml` — Private Zone 전용 ExternalDNS 생성
- [x] ExternalDNS policy를 `upsert-only`로 변경 (split-horizon 안정성)
- [x] IAM Policy scope — 특정 Hosted Zone ID로 제한
- [x] Dual Zone 동시 운영 테스트
- [x] `publish-service` 설정으로 Ingress ADDRESS 정상 노출
- [x] `pathOverride` 설정으로 nginx-ingress publishService 경로 수정

## 🔧 주요 변경 파일

| 파일 | 작업 |
|------|------|
| `gitops-apps/bootstrap/external-dns-private.yaml` | 🆕 Private Zone ExternalDNS |
| `gitops-apps/bootstrap/external-dns.yaml` | ✏️ policy: upsert-only |
| `gitops-apps/bootstrap/nginx-ingress.yaml` | ✏️ publishService 설정 |
| `stacks/dev/50-rke2/main.tf` | ✏️ IAM Policy scope 적용 |

## 📎 References

- [04-dns-strategy.md](../architecture/04-dns-strategy.md)
- [ExternalDNS 도입 티켓](2026-02-01-external-dns-ticket.md) — 선행 작업

## 🏷️ Labels

`dns`, `external-dns`, `split-horizon`, `route53`

## 📌 Priority / Status

**High** / ✅ 완료 (2026-02-02~03)
