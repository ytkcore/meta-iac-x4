# NLB 아키텍처 & 로드밸런서 컴포넌트 가이드

**작성일**: 2026-02-07  
**관련 컴포넌트**: NLB, nginx-ingress, AWS CCM, AWS Load Balancer Controller  
**환경**: dev-meta RKE2 클러스터, AWS ap-northeast-2

---

## 1. 아키텍처 개요

```
                    ┌─────────────────────────────────────────────────────┐
                    │                      VPC                           │
  Internet          │                                                     │
  ────────┐         │   ┌──────────────┐      ┌─────────────────────┐    │
  사용자   ├─────────┤──→│ Public NLB   │──┐   │ nginx-ingress Pods  │    │
  ────────┘         │   │ (internet)   │  ├──→│ (Public controller) │──┐ │
                    │   └──────────────┘  │   └─────────────────────┘  │ │
                    │                     │                            ├─┤──→ App Pods
  Teleport EC2 ─────┤──→┌──────────────┐  │   ┌─────────────────────┐  │ │
  (내부관리)        │   │ Internal NLB │──┘   │ nginx-ingress Pods  │──┘ │
                    │   │ (internal)   │──────│ (Internal controller)│    │
                    │   └──────────────┘      └─────────────────────┘    │
                    └─────────────────────────────────────────────────────┘
```

| 구분 | Public NLB | Internal NLB |
|------|-----------|-------------|
| 용도 | 고객 대상 웹서비스 | 내부 관리 UI (Teleport 경유) |
| Scheme | `internet-facing` | `internal` |
| 대상 서비스 | 향후 웹서비스 | Grafana, Longhorn, Rancher, ArgoCD |
| DNS Zone | Public Zone | Private Zone |

---

## 2. 컴포넌트 역할 구분

### 2.1 nginx-ingress Controller

**역할**: L7 라우팅 (Host/Path 기반 트래픽 분배)

```
NLB → nginx-ingress → Host header 확인 → 해당 Backend Pod으로 전달
```

- NLB가 전달한 트래픽을 Ingress 규칙에 따라 올바른 Pod으로 라우팅
- TLS 종료 (SSL Passthrough 또는 Offloading)
- 로드밸런서가 **아님** — K8s Ingress 규칙의 실행자

### 2.2 AWS Cloud Controller Manager (CCM)

**역할**: K8s ↔ AWS 연동 (3가지)

| 기능 | 설명 | 대체 가능? |
|------|------|-----------|
| **Node 관리** | EC2 메타데이터 → K8s Node 정보 동기화 (IP, Zone, 종료 감지) | ❌ 대체 불가 |
| **Route 관리** | Pod 네트워크 라우팅 (VPC CNI) | ❌ 대체 불가 |
| **LoadBalancer** | `Service(LB)` → NLB/ELB 생성 + Target 등록 | ✅ ALBC로 대체 |

> **현재 상태**: CCM이 NLB를 생성하지만 **Target Group에 Worker Node를 등록하지 않는 버그** 발생.  
> 원인 추정: RKE2 in-tree cloud provider와 external CCM 간 conflict.

### 2.3 AWS Load Balancer Controller (ALBC) — 미설치

**역할**: CCM의 LoadBalancer 기능을 완전 대체 + 강화

| 항목 | CCM (현재) | ALBC (권장) |
|------|-----------|------------|
| Target 유형 | **Instance** (Worker Node IP:NodePort) | **IP** (Pod IP 직접) |
| 경로 | NLB → Worker → kube-proxy → Pod (2-hop) | NLB → Pod (1-hop) |
| Target 등록 | Worker Node 고정 | Pod 자동 증감 |
| NodePort | 필요 (30000-32767) | **불필요** |
| SG 관리 | NodePort 범위 수동 개방 | 자동 |
| Worker 추가 시 | **수동 TG 업데이트** ⚠️ | 자동 |

### 2.4 컴포넌트 관계도

```
                올바른 구성 (미래 목표)
                ┌──────────────────────────────────┐
                │                                  │
  CCM ─────────→│  Node 관리 + Route 관리          │ ← 항상 필요
                │  (LoadBalancer 기능 OFF)          │
                └──────────────────────────────────┘
                ┌──────────────────────────────────┐
                │                                  │
  ALBC ────────→│  NLB/ALB 생성 + IP mode Target   │ ← CCM의 LB 기능 대체
                │  (Pod IP 직접 등록, 자동 관리)    │
                └──────────────────────────────────┘
                ┌──────────────────────────────────┐
                │                                  │
  nginx-ingress→│  L7 라우팅 (Host/Path 분배)      │ ← LB 뒤에서 동작
                │  (NLB가 아닌 Ingress 규칙 처리)   │
                └──────────────────────────────────┘
```

---

## 3. 트래픽 Mode 비교

### 3.1 Instance Mode (현재 — CCM)

```
NLB ──→ Worker-01:32081 ──→ kube-proxy ──→ nginx-pod (어디에든)
    ──→ Worker-02:32081 ──→ kube-proxy ──→ nginx-pod
    ──→ Worker-03:32081 ──→ kube-proxy ──→ nginx-pod
    ──→ Worker-04:32081 ──→ kube-proxy ──→ nginx-pod

Target Group = Worker Node 4개 (고정)
경로 = 2-hop (NLB → Worker → Pod)
NodePort = 필요 (32081, 32419 등)
```

- TG에 등록할 대상: **Worker EC2 Instance ID + NodePort**
- Worker Node가 추가/제거되면 **수동 TG 업데이트** 필요
- kube-proxy가 다른 Node의 Pod으로 전달할 수 있어 **cross-node hop** 발생

### 3.2 IP Mode (권장 — ALBC)

```
NLB ──→ 10.42.1.15:80  (nginx-pod-A 직접)
    ──→ 10.42.3.22:80  (nginx-pod-B 직접)

Target Group = Pod IP (스케일 따라 자동 증감)
경로 = 1-hop (NLB → Pod 직접)
NodePort = 불필요
```

- TG에 등록할 대상: **Pod IP + Container Port**
- Pod 스케일 시 **자동** 증감
- Worker Node 수와 무관
- cross-node hop 없음 → **성능 향상**

---

## 4. 현재 운영 제약사항

### 4.1 CCM Bug로 인한 수동 운영

| 항목 | 상태 |
|------|------|
| Internal NLB Target 등록 | **수동** (4 Worker × 2 TG = 8 targets) |
| Worker Node 추가 시 | **수동 TG 업데이트 필요** ⚠️ |
| Private Zone DNS | Ingress annotation 유지 필수 (`external-dns.alpha.kubernetes.io/target`) |
| Public NLB Target | 현재 불필요 (웹서비스 미배포) |

### 4.2 external-dns 덮어쓰기 주의

external-dns-private가 Ingress의 ADDRESS(Public NLB)를 기반으로 Private Zone DNS를 설정하므로,
수동 Route53 수정은 **external-dns에 의해 덮어쓰여질 수 있음**.

**해결**: Ingress에 `external-dns.alpha.kubernetes.io/target` annotation을 반드시 유지.

### 4.3 Route53 Health Check 주의

NLB Alias 레코드의 `EvaluateTargetHealth: true` 설정 시, TG가 unhealthy/empty이면 DNS가 아예 응답하지 않음.
초기 설정 시 `false`로 설정 권장.

---

## 5. 향후 개선: ALBC 도입

### 도입 시 변경 사항

```diff
- CCM이 NLB Target 관리 (Instance mode, 수동)
+ ALBC가 NLB Target 관리 (IP mode, 자동)

- Worker Node 추가마다 수동 TG 업데이트
+ Pod 스케일 시 자동 TG 업데이트

- NodePort 범위 SG 개방 필요
+ NodePort 불필요, SG 자동 관리
```

### 설치 절차 (개요)

1. IAM OIDC Provider 설정 (RKE2는 수동 구성 필요)
2. ALBC용 IAM Role + Policy 생성
3. Helm으로 ALBC 설치 (`aws-load-balancer-controller`)
4. Service annotation 변경:
   ```yaml
   # 기존 (CCM용)
   service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
   
   # 변경 (ALBC용)
   service.beta.kubernetes.io/aws-load-balancer-type: "external"  
   service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
   service.beta.kubernetes.io/aws-load-balancer-scheme: "internal"
   ```
5. 기존 NLB 재생성 (annotation 변경으로 새 NLB 생성됨)

> ⚠️ ALBC 도입은 NLB 재생성을 수반하므로 **DNS + Target 재설정** 필요. 별도 Jira 티켓으로 관리 권장.

---

## 6. EKS vs RKE2 비교

| 항목 | EKS | RKE2 (현재) |
|------|-----|------------|
| CCM | AWS 내장 (자동) | 별도 설치 (DaemonSet) |
| ALBC | Add-on 1클릭 설치 | Helm 수동 설치 + IAM 수동 구성 |
| OIDC Provider | 자동 | 수동 구성 필요 |
| Target 등록 | 자동 (IP mode 기본) | 수동 (CCM bug) |
| NLB 생성 | 자동 | 자동 (생성은 됨) |
| 운영 부담 | 낮음 | **높음** ⚠️ |

RKE2를 유지하는 명확한 이유 (라이선스, 멀티클라우드 등)가 있다면 ALBC 도입으로 운영 부담 경감.
없다면 장기적으로 EKS 전환이 운영 효율성 관점에서 유리.
