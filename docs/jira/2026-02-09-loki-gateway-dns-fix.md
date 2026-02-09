# [FIX] Loki Gateway CrashLoopBackOff — RKE2 CoreDNS Resolver 수정

## 📋 Summary

Loki Gateway(nginx 프록시)가 **CrashLoopBackOff**(78회 재시작)로 장애.
RKE2 환경에서 CoreDNS 서비스명이 표준 K8s와 달라 nginx resolver 해석 실패.

## 🎯 Root Cause

| 항목 | 내용 |
|------|------|
| 증상 | `loki-gateway` Pod CrashLoopBackOff, ArgoCD Degraded/OutOfSync |
| 에러 | `host not found in resolver "kube-dns.kube-system.svc.cluster.local."` |
| 원인 | RKE2 CoreDNS 서비스명: `rke2-coredns-rke2-coredns` (표준 `kube-dns` 없음) |
| 해결 | Helm values에서 `gateway.nginxConfig.resolver` 직접 지정 |

## 📋 Tasks

- [x] RKE2 control plane에서 CoreDNS 서비스명 확인 (SSM)
- [x] Loki gateway ConfigMap의 nginx.conf resolver 설정 확인
- [x] `loki.yaml` Helm values — `gateway.nginxConfig.resolver` 오버라이드
- [x] Git push → ArgoCD auto-sync 자동 반영

## 🔧 변경 파일

| 파일 | 변경 |
|------|------|
| `gitops-apps/bootstrap/loki.yaml` | gateway.nginxConfig.resolver 추가 |

## 📎 Commits

| Hash | 설명 |
|------|------|
| `2df51cd` | Loki gateway DNS resolver → rke2-coredns FQDN |

## 💡 Learnings

- **RKE2 DNS 서비스명**: `rke2-coredns-rke2-coredns.kube-system.svc.cluster.local` (표준 K8s의 `kube-dns`와 다름)
- **ClusterIP**: `10.43.0.10` (표준과 동일)
- Helm chart가 `kube-dns`를 기본 resolver로 사용하는 경우, RKE2에서는 반드시 오버라이드 필요

## 🏷️ Labels

`loki`, `observability`, `rke2`, `bugfix`, `dns`

## 📌 Priority / Status

**High** | ✅ **Done**
