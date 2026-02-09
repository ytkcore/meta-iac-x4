# Jira 티켓 인덱스

> **최종 업데이트**: 2026-02-08  
> **근거**: [16-architecture-evolution-decision.md](../architecture/16-architecture-evolution-decision.md)

---

## 📊 플랫폼 고도화 Phase 현황

| Phase | 작업 | 상태 | 티켓 |
|:------|:-----|:-----|:-----|
| 1 | ALBC + NLB IP Mode | ⏸️ Phase 6에서 해소 | [albc-adoption](2026-02-07-albc-adoption.md) |
| 1-2-4 | ALBC + Keycloak + Vault 실제 배포 | ✅ 완료 | [deployment](2026-02-07-keycloak-albc-vault-deployment.md) |
| 3 | Vault AWS Secrets Engine (Workload Identity) | ✅ 완료 | [milestones §Phase 3](2026-02-07-architecture-evolution-milestones.md) |
| 5 | CCM 제거 | ⏸️ Phase 6에서 해소 | [milestones §Phase 5](2026-02-07-architecture-evolution-milestones.md) |
| **6** | **Cilium CNI + 클러스터 재구축** | 🆕 **최우선** | [cilium-cni-migration](2026-02-08-cilium-cni-migration.md) |
| 6+ | Keycloak K8s 마이그레이션 | 🆕 Phase 6 동시 | [keycloak-k8s-migration](2026-02-08-keycloak-k8s-migration.md) |

---

## 📁 전체 티켓 목록 (날짜순)

### 2026-02-01 — ExternalDNS + check-status + TLS 착수

| 파일 | 제목 | 상태 |
|:-----|:-----|:-----|
| [external-dns-ticket](2026-02-01-external-dns-ticket.md) | ExternalDNS 도입 및 최소 권한 적용 | ✅ 완료 |
| [make-status-dashboard](2026-02-01-make-status-dashboard.md) | Intelligent Stack Status Dashboard (OPS-202) | ✅ 완료 |
| [tls-letsencrypt-migration](2026-02-01-tls-letsencrypt-migration.md) | TLS 체계 전환 — cert-manager + Let's Encrypt | ✅ 완료 |

### 2026-02-02 — 인프라 기초 + 복원력

| 파일 | 제목 | 상태 |
|:-----|:-----|:-----|
| [infra-foundation-tickets](2026-02-02-infra-foundation-tickets.md) | INFRA-001~005 기초 인프라 티켓 5건 | 📋 Draft |
| [infra-resilience](2026-02-02-infra-resilience-destroy-automation.md) | Destroy 자동화 + Remote State Resilience | ✅ 완료 |

### 2026-02-03 — Split-Horizon DNS + CCM + Observability

| 파일 | 제목 | 상태 |
|:-----|:-----|:-----|
| [split-horizon-dns](2026-02-03-split-horizon-dns.md) | Split-Horizon DNS — ExternalDNS Dual Zone 분리 | ✅ 완료 |
| [ccm-observability](2026-02-03-ccm-observability-stack.md) | AWS CCM 통합 + Observability 스택 구축 | ✅ 완료 |

### 2026-02-04 — Golden Image + Teleport HA

| 파일 | 제목 | 상태 |
|:-----|:-----|:-----|
| [golden-image-restructure](2026-02-04-golden-image-stack-restructure.md) | Golden Image v2 + 전체 스택 재구조화 | ✅ 완료 |
| [teleport-ha](2026-02-04-teleport-ha-access-control.md) | Teleport HA 배포 + Access Control 체계 | ✅ 완료 |
| [teleport-kube-agent-pod](2026-02-04-teleport-kube-agent-pod.md) | Teleport Kube Agent Pod 배포 | ✅ 완료 |
| [ssh-operational-policy](2026-02-04-ssh-operational-policy.md) | SSH 운영 정책 표준화 수립 | ✅ 완료 |

### 2026-02-06 — Bugfix

| 파일 | 제목 | 상태 |
|:-----|:-----|:-----|
| [longhorn-hook-fix](2026-02-06-longhorn-hook-fix.md) | Longhorn Pre-upgrade Hook 수정 | ✅ 완료 |

### 2026-02-07 — Dual NLB + 고도화 설계 + Phase 1-2-4 배포

| 파일 | 제목 | 상태 |
|:-----|:-----|:-----|
| [cert-manager-dns01-dual-nlb](2026-02-07-cert-manager-dns01-dual-nlb.md) | cert-manager DNS-01 전환 + Dual NLB 구축 | ✅ 완료 |
| [keycloak-albc-vault-deployment](2026-02-07-keycloak-albc-vault-deployment.md) | ALBC + Keycloak + Vault Phase 1-2-4 실제 배포 | ✅ 완료 |
| [architecture-evolution-decision](2026-02-07-architecture-evolution-decision.md) | 아키텍처 고도화 최종 의사결정 | ✅ 확정 |
| [architecture-evolution-milestones](2026-02-07-architecture-evolution-milestones.md) | 마일스톤별 구현 티켓 (Phase 1~6) | 📋 로드맵 |
| [albc-adoption](2026-02-07-albc-adoption.md) | AWS Load Balancer Controller 도입 | ⏸️ Phase 6 |
| [keycloak-idp-adoption](2026-02-07-keycloak-idp-adoption.md) | Keycloak 통합 IdP 도입 | ✅ 설계 |
| [nlb-target-automation](2026-02-07-nlb-target-automation.md) | NLB 수동 Target 등록 자동화 | ⏸️ Phase 6 |
| [access-gateway-stack](2026-02-07-access-gateway-stack.md) | 80-access-gateway 스택 구현 | 📋 계획 |
| [web-service-onboarding](2026-02-07-web-service-onboarding.md) | 웹서비스 온보딩 표준 절차 | 📋 계획 |

### 2026-02-08 — Cilium + ArgoCD Drift Fix

| 파일 | 제목 | 상태 |
|:-----|:-----|:-----|
| [cilium-cni-migration](2026-02-08-cilium-cni-migration.md) | Cilium ENI Mode 전환 + Clean Rebuild | 🆕 **Critical** |
| [keycloak-k8s-migration](2026-02-08-keycloak-k8s-migration.md) | Keycloak EC2 → K8s-native 마이그레이션 | 🆕 Phase 6 동시 |
| [argocd-drift-fix](2026-02-08-argocd-drift-fix.md) | ArgoCD OutOfSync Drift 수정 | 🔄 부분 완료 |
| [vault-aws-se-albc](2026-02-08-vault-aws-se-albc.md) | Vault AWS SE — ALBC Workload Identity | ✅ 완료 |
| [cluster-stabilization](2026-02-08-cluster-stabilization.md) | CCM 정리 + 관리도구 Internal 전환 (11건) | ✅ 완료 |
| ↳ [sub-tickets/](2026-02-08-cluster-stabilization/) | T01~T11 상세 워크스루 (디렉토리) | ✅ 11건 |

### 2026-02-09 — Keycloak K8s 전환 실행 + 네트워크 디버깅

| 파일 | 제목 | 상태 |
|:-----|:-----|:-----|
| [keycloak-k8s-native-deployment](2026-02-09-keycloak-k8s-native-deployment.md) | Keycloak EC2 → K8s Native Deployment 실행 | ✅ 완료 |
| [nlb-sg-public-access-fix](2026-02-09-nlb-sg-public-access-fix.md) | NLB IP-mode Security Group 외부 접근 수정 | ✅ 완료 |
| [cilium-cnp-cross-namespace-fix](2026-02-09-cilium-cnp-cross-namespace-fix.md) | CiliumNetworkPolicy Cross-namespace 수정 | ✅ 완료 |
| [teleport-keycloak-rewrite-fix](2026-02-09-teleport-keycloak-rewrite-fix.md) | Teleport keycloak-admin rewrite.redirect 수정 | ✅ 완료 |
| [argocd-secret-security-hardening](2026-02-09-argocd-secret-security-hardening.md) | ArgoCD Secret 보안 강화 — Prune 방지 + 평문 제거 | ✅ 완료 |
| [infra-codification-sg-teleport](2026-02-09-infra-codification-sg-teleport.md) | SG 코드화 + Teleport Observability 앱 등록 | ✅ 완료 |
| [loki-gateway-dns-fix](2026-02-09-loki-gateway-dns-fix.md) | Loki Gateway CrashLoopBackOff — RKE2 CoreDNS Resolver | ✅ 완료 |

---

## 📅 일자별 커버리지 요약

| 날짜 | 요일 | 🎯 메인 Task | 핵심 산출물 | 티켓 |
|:-----|:-----|:------------|:----------|:-----|
| **2/1** | 토 | **GitOps 기반 서비스 배포 기틀 구축** | ExternalDNS, check-status, cert-manager ClusterIssuer, CCM 착수 | 3 |
| **2/2** | 일 | **인프라 복원력 + 자동 삭제 체계 확립** | `make destroy-all` 100% 자동화, `try()` 전수 적용, DNS Hygiene | 2 |
| **2/3** | 월 | **네트워크 관측성 확보** | Split-Horizon DNS, CCM NLB 자동화, Longhorn + Grafana/Prometheus | 2 |
| **2/4** | 화 | **접근 제어 체계 전환 (VPN → Teleport)** | Golden Image v2, 스택 재넘버링(05/10/15/20), Teleport HA + WAF | 2 |
| **2/5** | 수 | *(2/4 Teleport 후속 문서화)* | Access Control 문서 7건 | — |
| **2/6** | 목 | **ArgoCD 앱 안정화** | Longhorn hook race condition 해결 | 1 |
| **2/7** | 금 | **플랫폼 고도화 설계 + Phase 1-2-4 배포** | DNS-01 전환, Dual NLB, Keycloak SSO, ALBC, Vault | 9 |
| **2/8** | 토 | **Vault Workload Identity + Cilium 계획 + SSO** | Vault AWS SE, Cilium ENI, ArgoCD Drift Fix, Keycloak SSO | 6 |
| **2/9** | 일 | **Keycloak K8s 전환 + 보안 강화 + Loki 수정** | K8s Deployment, SG/CNP/Teleport Fix, Secret 보안, Loki DNS | 7 |

### 🔑 주간 핵심 흐름

```
2/1  서비스 배포 기틀 (DNS + TLS + CCM)
 ↓
2/2  파괴 안정성 확보 (Destroy 자동화 + Resilience)
 ↓
2/3  관측성 구축 (Monitoring + Dual DNS + NLB)
 ↓
2/4  접근 제어 전환 (VPN 제거 → Teleport HA + Golden Image v2)
 ↓
2/6  ArgoCD 앱 안정화 (Longhorn Hook Fix)
 ↓
2/7  ★ 플랫폼 고도화 Day — ALBC + Keycloak + Vault + Dual NLB
 ↓
2/8  ★ Vault Workload Identity — ALBC 동적 STS 자격증명 + Cilium 전환 계획
 ↓
2/9  ★ Keycloak K8s 전환 — EC2 탈피 + SG/CNP/Teleport 디버깅
```

### 📈 성과 지표

| 지표 | 값 |
|:-----|:---|
| 총 커밋 수 | 62+ |
| 신규 Terraform 모듈 | 5개 (`albc-iam`, `keycloak-ec2`, `teleport-ec2`, `waf-acl`, `ec2-instance` 개선) |
| 신규 Terraform 스택 | 5개 (`05-security`, `10-golden-image`, `15-teleport`, `20-waf`, `25-keycloak`) |
| 삭제 스택 | 1개 (`15-vpn`) |
| ArgoCD 앱 | 12+ 앱 자동 배포 |
| 문서 | 20+ 문서 (architecture, security, troubleshooting, guides) |
| Jira 티켓 | **33건** (이 디렉토리) |
