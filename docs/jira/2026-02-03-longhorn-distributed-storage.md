# Longhorn 분산 스토리지 도입 및 안정화

> **Status**: ✅ 완료  
> **Priority**: High  
> **Labels**: `longhorn`, `storage`, `observability`, `argocd`  
> **작업 기간**: 2026-02-03 ~ 2026-02-08  
> **주요 커밋**: `8538b65`, `ab814e1`, `ddc13a0`, `067fd2a`

---

## 🔍 Longhorn이란?

**Longhorn**은 Rancher(SUSE)가 개발한 **CNCF 인큐베이팅 프로젝트**로,
Kubernetes에 경량 분산 블록 스토리지를 제공하는 **CSI(Container Storage Interface) 드라이버**이다.

### 왜 Longhorn인가

| 비교 항목 | EBS CSI (AWS 종속) | Longhorn (CSP 독립) |
|:----------|:-------------------|:--------------------|
| **CSP 종속** | ✅ AWS 한정 | ❌ 어디서나 동작 |
| **복제** | AZ 내 자동 | 노드 간 N-replica |
| **스냅샷/백업** | EBS Snapshot | S3 / NFS 등 |
| **비용** | EBS 볼륨 과금 | 로컬 디스크 활용 |
| **멀티클라우드** | ❌ | ✅ On-prem, Edge 포함 |

> 고객 납품 시 AWS 이외 환경(On-prem, 타 CSP)에서도 동일한 스토리지 계층을
> 사용할 수 있도록 CSP 독립적인 Longhorn을 채택.

### 동작 구조

```
┌─ Worker Node 1 ──────────────┐
│  Longhorn Manager (DaemonSet) │  ← 스케줄링, 복제 관리
│  Longhorn Engine              │  ← 블록 I/O 처리
│  /var/lib/longhorn/ [Replica] │  ← 실제 데이터
└───────────────────────────────┘
         │ 동기 복제 (3-replica)
┌─ Worker Node 2 ──────────────┐
│  /var/lib/longhorn/ [Replica] │
└───────────────────────────────┘
         │
┌─ Worker Node 3 ──────────────┐
│  /var/lib/longhorn/ [Replica] │
└───────────────────────────────┘
         │ 주기적 백업
    [ S3 Bucket (DR) ]
```

- 각 Worker 노드에 **DaemonSet**으로 배포
- Pod이 PVC를 요청하면 **Dynamic Provisioning**으로 PV 자동 생성
- 데이터를 노드 간 **동기 복제(3-replica)** → 1노드 장애 허용
- S3로 **주기적 백업** → 재해 복구(DR) 대비

---

## 📋 요약

RKE2 클러스터에 **Longhorn v1.6.0 분산 블록 스토리지**를 도입하여
Observability, Vault 등 StatefulSet 워크로드의 PVC Dynamic Provisioning을 지원한다.
S3 백업, HA 3-replica, ArgoCD Drift Fix, Internal NLB 전환, Hook 버그 수정까지
도입부터 안정화까지의 전 과정을 포함한다.

---

## 🎯 목표

1. CSP 독립 분산 블록 스토리지 (`storageClassName: longhorn`) 제공
2. PVC Dynamic Provisioning → StatefulSet 자동 볼륨 할당
3. 3-replica HA + Hard Anti-Affinity (1노드 장애 허용)
4. S3 백업 자동화 (DR 대비)
5. Internal NLB 뒤로 관리 UI 보호

---

## 📂 변경 파일

| 파일 | 변경 |
|:-----|:-----|
| `gitops-apps/bootstrap/longhorn.yaml` | ArgoCD Application (Helm v1.6.0) |
| `stacks/dev/70-observability/` | S3 백업 버킷 + IAM Role |

---

## ✅ 작업 타임라인

### 2/3 — 최초 도입 (`8538b65`)

- [x] Longhorn v1.6.0 ArgoCD Application 생성
- [x] 70-observability 스택 → S3 백업 버킷 + IAM 프로비저닝
- [x] Monitoring(Prometheus/Grafana)과 동시 도입

### 2/6 — Hook 버그 수정 (`ab814e1`)

- [x] Pre-upgrade hook ServiceAccount race condition 해결
- [x] `preUpgradeChecker.jobEnabled: false` 설정

### 2/7 — Dual NLB (`e752828`)

- [x] Internal NLB 인프라 구축 (Longhorn UI 이동 대비)

### 2/8 — ArgoCD Drift Fix + 보안 (`ddc13a0`, `067fd2a`)

- [x] Longhorn DaemonSet/Deployment/Webhook `ignoreDifferences` 추가
- [x] Longhorn UI를 **Internal NLB**로 전환 (`nginx-internal`)
- [x] `priorityClass: system-cluster-critical` 설정

---

## 🔑 핵심 설정

### Helm Values 요약

| 항목 | 설정 | 의미 |
|:-----|:-----|:-----|
| **Replica** | 3 | 노드 1대 장애 허용 |
| **Anti-Affinity** | Hard | Replica가 반드시 다른 노드에 분산 |
| **Auto Balance** | best-effort | 노드 추가/제거 시 자동 리밸런싱 |
| **Backup** | `s3://dev-meta-longhorn-backup` | DR용 S3 백업 |
| **Priority** | system-cluster-critical | Manager/Driver Eviction 방지 |
| **Pre-upgrade Hook** | disabled | ServiceAccount race condition 방지 |
| **Ingress** | nginx-internal | Internal NLB 뒤 보호 |

### 의존 서비스 (PVC 사용처)

| 서비스 | PVC 용도 | 크기 |
|:-------|:---------|:-----|
| **Prometheus** | TSDB 메트릭 저장 | 20Gi |
| **Alertmanager** | 알림 상태 저장 | 5Gi |
| **Grafana** | 대시보드/데이터 | 10Gi |
| **Vault** | Raft 스토리지 | 10Gi |
| **Loki** | 로그 저장 | — |
| **Tempo** | 트레이싱 데이터 | — |

### K8s 스토리지 동작 흐름

```
Pod (e.g. Prometheus)
  → PVC 생성 (storageClassName: longhorn, 20Gi)
    → Longhorn CSI가 PV 자동 프로비저닝 (Dynamic Provisioning)
      → 3-replica로 Worker 노드 간 복제
        → S3 주기적 백업 (DR)
```

---

## 🔗 관련 티켓

- [ccm-observability-stack](2026-02-03-ccm-observability-stack.md) — 최초 도입 (CCM과 함께)
- [longhorn-hook-fix](2026-02-06-longhorn-hook-fix.md) — Pre-upgrade Hook 버그 수정 상세
- [argocd-drift-fix](2026-02-08-argocd-drift-fix.md) — ignoreDifferences 설정
- [cluster-stabilization](2026-02-08-cluster-stabilization.md) — Internal NLB 전환 포함
