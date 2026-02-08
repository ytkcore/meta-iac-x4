# Jira 티켓 인덱스

> **최종 업데이트**: 2026-02-08  
> **근거**: [16-architecture-evolution-decision.md](../architecture/16-architecture-evolution-decision.md)

---

## 📊 플랫폼 고도화 Phase 현황

| Phase | 작업 | 상태 | 티켓 |
|:------|:-----|:-----|:-----|
| 1 | ALBC + NLB IP Mode | ⏸️ Phase 6에서 해소 | [albc-adoption](2026-02-07-albc-adoption.md) |
| 2 | Keycloak SSO | ✅ 설계 완료 | [keycloak-idp-adoption](2026-02-07-keycloak-idp-adoption.md) |
| 3 | IAM OIDC Federation | ⏸️ Phase 6 이후 | [milestones §Phase 3](2026-02-07-architecture-evolution-milestones.md) |
| 4 | Vault Dynamic Secrets | ✅ 설계 완료 | [milestones §Phase 4](2026-02-07-architecture-evolution-milestones.md) |
| 5 | CCM 제거 | ⏸️ Phase 6에서 해소 | [milestones §Phase 5](2026-02-07-architecture-evolution-milestones.md) |
| **6** | **Cilium CNI + 클러스터 재구축** | 🆕 **최우선** | [cilium-cni-migration](2026-02-08-cilium-cni-migration.md) |
| 6+ | Keycloak K8s 마이그레이션 | 🆕 Phase 6 동시 | [keycloak-k8s-migration](2026-02-08-keycloak-k8s-migration.md) |

---

## 📁 전체 티켓 목록 (날짜순)

### 2026-02-01 — 운영 자동화

| 파일 | 제목 | 상태 |
|:-----|:-----|:-----|
| [external-dns-ticket](2026-02-01-external-dns-ticket.md) | ExternalDNS 도입 및 최소 권한 적용 | ✅ 완료 |
| [make-status-dashboard](2026-02-01-make-status-dashboard.md) | Intelligent Stack Status Dashboard (OPS-202) | ✅ 완료 |

### 2026-02-02 — 인프라 기초 + TLS + DNS + Resilience

| 파일 | 제목 | 상태 |
|:-----|:-----|:-----|
| [infra-foundation-tickets](2026-02-02-infra-foundation-tickets.md) | INFRA-001~005 기초 인프라 티켓 5건 | 📋 Draft |
| [tls-letsencrypt-migration](2026-02-02-tls-letsencrypt-migration.md) | TLS 체계 전환 — cert-manager + Let's Encrypt | ✅ 완료 |
| [split-horizon-dns](2026-02-02-split-horizon-dns.md) | Split-Horizon DNS — ExternalDNS Dual Zone 분리 | ✅ 완료 |
| [infra-resilience](2026-02-02-infra-resilience-destroy-automation.md) | 인프라 복원력 강화 — Destroy 자동화 + Resilience | ✅ 완료 |

### 2026-02-03 — CCM + Observability

| 파일 | 제목 | 상태 |
|:-----|:-----|:-----|
| [ccm-observability](2026-02-03-ccm-observability-stack.md) | AWS CCM 통합 + Observability 스택 구축 | ✅ 완료 |

### 2026-02-04 — Golden Image + Teleport HA

| 파일 | 제목 | 상태 |
|:-----|:-----|:-----|
| [golden-image-restructure](2026-02-04-golden-image-stack-restructure.md) | Golden Image v2 + 전체 스택 재구조화 | ✅ 완료 |
| [teleport-ha](2026-02-04-teleport-ha-access-control.md) | Teleport HA 배포 + Access Control 체계 구축 | ✅ 완료 |

### 2026-02-06 — Bugfix

| 파일 | 제목 | 상태 |
|:-----|:-----|:-----|
| [longhorn-hook-fix](2026-02-06-longhorn-hook-fix.md) | Longhorn Pre-upgrade Hook 수정 | ✅ 완료 |

### 2026-02-07 — 플랫폼 고도화 설계

| 파일 | 제목 | 상태 |
|:-----|:-----|:-----|
| [architecture-evolution-decision](2026-02-07-architecture-evolution-decision.md) | 아키텍처 고도화 최종 의사결정 | ✅ 확정 |
| [architecture-evolution-milestones](2026-02-07-architecture-evolution-milestones.md) | 마일스톤별 구현 티켓 (Phase 1~6) | 📋 로드맵 |
| [albc-adoption](2026-02-07-albc-adoption.md) | AWS Load Balancer Controller 도입 | ⏸️ Phase 6 |
| [keycloak-idp-adoption](2026-02-07-keycloak-idp-adoption.md) | Keycloak 통합 IdP 도입 | ✅ 설계 |
| [nlb-target-automation](2026-02-07-nlb-target-automation.md) | NLB 수동 Target 등록 자동화 | ⏸️ Phase 6 |
| [access-gateway-stack](2026-02-07-access-gateway-stack.md) | 80-access-gateway 스택 구현 | 📋 계획 |
| [web-service-onboarding](2026-02-07-web-service-onboarding.md) | 웹서비스 온보딩 표준 절차 | 📋 계획 |

### 2026-02-08 — 네트워크 진화 (Phase 6)

| 파일 | 제목 | 상태 |
|:-----|:-----|:-----|
| [cilium-cni-migration](2026-02-08-cilium-cni-migration.md) | Cilium ENI Mode 전환 + Clean Rebuild | 🆕 **Critical** |
| [keycloak-k8s-migration](2026-02-08-keycloak-k8s-migration.md) | Keycloak EC2 → K8s-native 마이그레이션 | 🆕 Phase 6 동시 |
