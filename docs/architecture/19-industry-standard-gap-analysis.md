# 글로벌 업계 표준 대비 아키텍처 Gap Analysis

**작성일**: 2026-02-10  
**기준**: CNCF Cloud Native Maturity Model v4.0, K8s Production Readiness Checklist, Platform Engineering Standards  
**대상**: 현재 v0.5 아키텍처 (3-Layer Identity Stack)

> 현재 아키텍처를 글로벌 업계 정석과 비교하여  
> **이미 갖춘 것**, **반영 권장 사항**, **현재 불필요/시기상조인 것**을 구분합니다.

---

## 📊 전체 Maturity Scorecard

| 영역 | 현재 수준 | 업계 표준 | 갭 | 우선순위 |
|:-----|:---------|:---------|:---|:--------|
| **GitOps / IaC** | ⭐⭐⭐⭐⭐ | Git SSOT + ArgoCD | ✅ 달성 | — |
| **Identity / SSO** | ⭐⭐⭐⭐ | Keycloak + OIDC | ✅ 달성 | SSO 연동 마무리 |
| **Secrets Management** | ⭐⭐⭐⭐ | Vault + 동적 시크릿 | ✅ 달성 | DB dynamic secrets 적용 |
| **Access Control** | ⭐⭐⭐⭐⭐ | Zero-Trust + MFA | ✅ 달성 | — |
| **Observability** | ⭐⭐⭐ | 3 Pillars (Metrics/Logs/Traces) | ⚠️ 부분 | Logging + Tracing 미비 |
| **Supply Chain Security** | ⭐⭐ | Image Signing + SBOM + Scanning | 🔴 미비 | 권장 |
| **Disaster Recovery** | ⭐⭐ | etcd Backup + Velero + Cross-AZ | 🔴 미비 | **필수** |
| **Resource Management** | ⭐⭐ | HPA/VPA + Requests/Limits + LimitRange | ⚠️ 부분 | 권장 |
| **Policy-as-Code** | ⭐ | OPA/Kyverno + Pod Security | 🔴 미비 | 권장 |
| **CI/CD Pipeline** | ⭐ | Progressive Delivery + Canary | 🔴 미비 | 향후 |

---

## ✅ 이미 업계 표준을 달성한 영역

### 1. GitOps (CNCF Level 5)

| 항목 | 상태 |
|:-----|:-----|
| Git = Single Source of Truth | ✅ ArgoCD App-of-Apps |
| Declarative Everything | ✅ Terraform + YAML |
| Continuous Reconciliation | ✅ ArgoCD selfHeal |
| Drift Detection | ✅ ArgoCD sync status |

> **평가**: GitOps 영역은 **이미 업계 최상위 수준**. CNCF Maturity Level 5(Adapt) 해당.

### 2. Identity & Access (3-Layer Stack)

| 항목 | 상태 |
|:-----|:-----|
| Keycloak SSO (OIDC) | ✅ v25 Hostname v2 |
| Vault (Secrets + Workload ID) | ✅ KMS Auto-Unseal + AWS SE |
| Teleport (Zero-Trust Access) | ✅ SSH + K8s + DB + Web App |
| MFA | ✅ Teleport MFA |
| Session Recording | ✅ Teleport |

> **평가**: Atlan(시장 선두)과 **사실상 동일 구성**. 시장 검증 완료.

### 3. Network Architecture

| 항목 | 상태 |
|:-----|:-----|
| Dual NLB (Public/Internal) | ✅ |
| Dual Ingress Controller | ✅ |
| TLS Automation (DNS-01) | ✅ cert-manager |
| Split-Horizon DNS | ✅ external-dns |
| WAF | ✅ AWS WAF ACL |

### 4. Infrastructure as Code

| 항목 | 상태 |
|:-----|:-----|
| Terraform Modular Stacks | ✅ 15+ stacks |
| Golden Image (Packer) | ✅ |
| make wrapper (DX) | ✅ |
| State Surgery 역량 | ✅ |

---

## 🔴 반영을 적극 권장하는 영역 (Quick Wins 우선)

### 1. 🔴 Disaster Recovery — etcd Backup + Velero

**현재**: etcd 백업 체계 없음, PV 백업 없음  
**업계 표준**: 자동 etcd snapshot + Velero + 크로스 리전 복구 + 정기 DR 훈련

| 항목 | 현재 | 권장 |
|:-----|:-----|:-----|
| etcd Backup | ❌ 없음 | `etcdctl snapshot` cron (1시간) → S3 |
| K8s Resource Backup | ❌ 없음 | **Velero** (Deployments, Secrets, CRDs) |
| PV Backup | ❌ 없음 | Velero + Longhorn S3 backup |
| RTO/RPO 정의 | ❌ 없음 | 목표: RPO 1h, RTO 4h |
| DR 훈련 | ❌ 없음 | 월 1회 복구 테스트 |

> [!CAUTION]
> **etcd 데이터 유실 = 클러스터 전체 복구 불가.** 현재 가장 큰 리스크.
> Longhorn S3 backup은 PV만 커버하고, K8s 오브젝트(Deployment, Secret, ConfigMap)는 미보호.

**구현 난이도**: 🟢 낮음 (Velero Helm 1개 + etcd cron 1개)  
**비즈니스 임팩트**: 🔴 극히 높음

---

### 2. 🔴 Observability 3 Pillars — Logging + Tracing

**현재**: Metrics만 충족 (Prometheus + Grafana). Logs/Traces 미비  
**업계 표준**: Metrics + Logs + Traces = 3 Pillars (CNCF Observability 표준)

| Pillar | 현재 | 권장 |
|:-------|:-----|:-----|
| **Metrics** | ✅ Prometheus + Grafana | 유지 |
| **Logs** | ⚠️ Loki (배포됨, 불안정) | Loki 안정화 또는 **Fluentd → OpenSearch** |
| **Traces** | ❌ 없음 | **OpenTelemetry** + Tempo 또는 Jaeger |
| **Golden Signals** | ❌ 미정의 | Latency/Traffic/Errors/Saturation 대시보드 |
| **Alerting** | ⚠️ 기본만 | 증상 기반 Alert + Runbook 연결 |

> [!IMPORTANT]
> **Traces**는 Keycloak SSO 흐름(사용자 → Teleport → Keycloak → 서비스)에서 병목 진단에 필수.  
> OpenTelemetry는 **CNCF Graduated 프로젝트**로 2025 업계 De facto.

**구현 난이도**: 🟡 중간  
**비즈니스 임팩트**: 🟡 중간 (운영 성숙도)

---

### 3. 🔴 Supply Chain Security — Image Signing + Scanning

**현재**: Harbor에 이미지 저장, 서명/스캔 없음  
**업계 표준**: Cosign(Sigstore) 서명 + Trivy 스캐닝 + SBOM + Admission Policy

| 항목 | 현재 | 권장 |
|:-----|:-----|:-----|
| Image Signing | ❌ 없음 | **Cosign** (Keyless OIDC signing) |
| Vulnerability Scanning | ❌ 없음 | **Trivy** (Harbor 내장 or CI/CD) |
| SBOM | ❌ 없음 | **Syft** (Harbor 연동) |
| Admission Control | ❌ 없음 | Sigstore Policy Controller or Kyverno |
| Image Pinning | ⚠️ `:latest` 혼재 | `digest` pinning 권장 |

> [!WARNING]
> **Harbor**에 **Trivy 스캐너가 내장**되어 있어 설정만 활성화하면 바로 사용 가능.
> 이것만으로도 CVE 스캐닝 커버 가능 — **가장 쉬운 Quick Win.**

**구현 난이도**: 🟢 낮음 (Harbor Trivy 활성화는 설정 변경 1건)  
**비즈니스 임팩트**: 🟡 중간 (컴플라이언스, 고객 감사)

---

### 4. 🔴 Policy-as-Code — Kyverno / OPA Gatekeeper

**현재**: Pod Security 정책 없음, RBAC 최소  
**업계 표준**: Pod Security Admission + Policy Engine + 자동 규정 준수

| 항목 | 현재 | 권장 |
|:-----|:-----|:-----|
| Pod Security Standards | ❌ 없음 | K8s PSA (baseline/restricted) |
| Policy Engine | ❌ 없음 | **Kyverno** (K8s-native, 학습 곡선 낮음) |
| RBAC Audit | ❌ 수동 | 정기 RBAC 리뷰 자동화 |
| NetworkPolicy 기본값 | ⚠️ CiliumNP 일부 | Default Deny + 명시적 Allow |

> [!NOTE]
> **Kyverno vs OPA Gatekeeper**: Kyverno가 K8s-native YAML 기반으로 학습 곡선이 낮고, 
> CiliumNetworkPolicy와 조합이 좋음. Cilium 전환 후 함께 적용 권장.

**구현 난이도**: 🟡 중간  
**비즈니스 임팩트**: 🟡 중간 (컴플라이언스)

---

### 5. ⚠️ Resource Management — Requests/Limits + Autoscaling

**현재**: 대부분 워크로드에 resource requests/limits 미설정  
**업계 표준**: 모든 Pod에 requests/limits + Namespace ResourceQuota + HPA/VPA

| 항목 | 현재 | 권장 |
|:-----|:-----|:-----|
| Resource Requests/Limits | ⚠️ 일부만 | **모든 워크로드에 설정** |
| Namespace ResourceQuota | ❌ 없음 | 핵심 NS에 LimitRange + Quota |
| HPA | ❌ 없음 | 트래픽 변동 워크로드에 적용 |
| VPA | ❌ 없음 | 검토 후 적용 |
| Liveness/Readiness Probes | ⚠️ 일부만 | **모든 워크로드에 설정** |
| PDB (Pod Disruption Budget) | ❌ 없음 | 핵심 서비스에 적용 |

**구현 난이도**: 🟢 낮음 (YAML 수정)  
**비즈니스 임팩트**: 🟡 중간 (안정성, Cilium 전환 시 필수)

---

## 🟡 향후 검토 권장 (현재 규모에서는 시기상조)

### 6. CI/CD Pipeline — Progressive Delivery

| 항목 | 현재 | 업계 표준 | 판단 |
|:-----|:-----|:---------|:-----|
| CI/CD Pipeline | GitHub Actions (기본) | Tekton / GitHub Actions + Argo Rollouts | ⏸️ |
| Canary / Blue-Green | ❌ | Argo Rollouts + Istio/Cilium | ⏸️ 서비스 메시 도입 시 |
| Image Build | 수동 | Kaniko + 자동 빌드 + 서명 | ⏸️ 앱 개발 시작 시 |

> 현재는 인프라/플랫폼 구축 단계이므로 **앱 개발이 본격화되면** 도입.

### 7. Internal Developer Platform (IDP) — Backstage

| 항목 | 현재 | 업계 표준 | 판단 |
|:-----|:-----|:---------|:-----|
| Service Catalog | ❌ | Backstage | ⏸️ 마이크로서비스 5개+ 시 |
| Golden Path Templates | ❌ | Backstage Scaffolder | ⏸️ |
| Developer Portal | ❌ | Backstage + TechDocs | ⏸️ |

> **개발자 3명 이상, 서비스 5개 이상** 시점에서 검토. 현재 규모에서는 오버헤드.

### 8. FinOps / Cost Optimization

| 항목 | 현재 | 업계 표준 | 판단 |
|:-----|:-----|:---------|:-----|
| Cost Visibility | ❌ | Kubecost / OpenCost | ⏸️ 프로덕션 진입 후 |
| Right-sizing | ❌ | VPA + Goldilocks | ⏸️ |
| Spot Instances | ❌ | Worker Node Spot Mix | ⏸️ 안정화 후 |

### 9. Multi-Cluster / Fleet Management

| 항목 | 현재 | 업계 표준 | 판단 |
|:-----|:-----|:---------|:-----|
| Multi-Cluster | 단일 | Cluster API (CAPI) | ⏸️ 고객 납품 시 |
| Fleet Governance | N/A | Rancher Fleet / ArgoCD ApplicationSet | ⏸️ |

> RKE2 + Rancher 조합에서 **Rancher가 Fleet Management를 이미 제공**. 필요 시 활성화만 하면 됨.

---

## 📋 권장 우선순위 로드맵

```
즉시 (Quick Win, 1-2일):
 ├── Harbor Trivy 스캐너 활성화 (설정 변경)
 ├── etcd 자동 백업 cron 설정
 └── 핵심 워크로드 resource requests/limits 추가

단기 (1-2주):
 ├── Velero 설치 + S3 backup 설정
 ├── Loki 안정화 (또는 대체)
 ├── K8s PSA (Pod Security Admission) baseline 적용
 └── Keycloak SSO 실제 연동 (Grafana, ArgoCD)

중기 (Cilium 전환과 함께):
 ├── Kyverno Policy Engine 도입
 ├── Default Deny NetworkPolicy
 ├── OpenTelemetry + Tempo (Traces)
 └── PDB + HPA 설정

향후 (앱 개발 본격화 시):
 ├── Cosign Image Signing + SBOM
 ├── Argo Rollouts (Canary/Blue-Green)
 ├── Backstage (IDP)
 └── Kubecost (FinOps)
```

---

## 📈 현재 CNCF Maturity Level 평가

```
[Level 1: Build]    ████████████████████ 100% ✅
[Level 2: Operate]  ████████████████░░░░  80% ✅ (DR 미비)
[Level 3: Scale]    ██████████░░░░░░░░░░  50% ⚠️ (HPA/VPA, ResourceQuota 없음)
[Level 4: Improve]  ██████░░░░░░░░░░░░░░  30% ⚠️ (Policy-as-Code, Supply Chain)
[Level 5: Adapt]    ████░░░░░░░░░░░░░░░░  20% ⏸️ (FinOps, IDP, Multi-Cluster)
```

> **현재 위치**: Level 2~3 사이. **Level 3 완성이 현실적 단기 목표.**
> Level 4+는 Cilium 전환 + 앱 개발 본격화 이후.

---

## 🎯 핵심 결론

| # | 결론 |
|---|------|
| 1 | **Identity/Access/Secrets는 이미 업계 최상위** — Atlan급 아키텍처 달성 |
| 2 | **가장 큰 리스크는 DR(Disaster Recovery)** — etcd/K8s 리소스 백업 없음 |
| 3 | **가장 쉬운 Quick Win은 Harbor Trivy** — 설정 변경 1건으로 CVE 스캐닝 |
| 4 | **Observability 3 Pillars 중 Traces가 부재** — SSO 흐름 진단에 필요 |
| 5 | **Cilium 전환 시 Kyverno + PSA를 함께 적용**하면 Level 4 진입 가능 |

---

## 참고

- [CNCF Cloud Native Maturity Model v4.0](https://maturitymodel.cncf.io/)
- [16-architecture-evolution-decision.md](16-architecture-evolution-decision.md) — 현재 아키텍처 의사결정
- [18-architecture-evolution-story.md](18-architecture-evolution-story.md) — 아키텍처 진화 스토리
