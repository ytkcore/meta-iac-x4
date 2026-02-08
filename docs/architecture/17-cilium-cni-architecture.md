# Cilium CNI 아키텍처 — 네트워크 기반 전환 의사결정

**작성일**: 2026-02-08  
**상태**: 확정  
**범위**: RKE2 CNI 교체 (Canal → Cilium ENI Mode) + 클러스터 재구축

---

## 0. 의사결정 히스토리 — 이 결론에 이르기까지

이 문서는 NLB IP-mode Target Health 장애를 진단하는 과정에서, **근본 원인이 overlay networking 자체에 있음**을 확인하고, 임시 해결이 아닌 **플랫폼 네트워크 기반 자체를 교체**하는 결정에 도달한 경위를 기록한다.

### 의사결정 흐름

```
NLB Target unhealthy → 왜 Pod IP에 도달 못하지?
  → VPC Route Table에 Pod CIDR 경로가 없다 → CCM이 Route를 안 만들고 있다
    → --configure-cloud-routes=false + providerID 미설정 → 패치하면 되나?
      → 잠깐, 외부 공개가 필요한 서비스가 Keycloak 하나뿐이다
        → 글로벌 표준은? → K8s-native Keycloak + Dual Ingress
          → 그래도 NLB가 동작해야 하는데... → 근본 원인: overlay networking
            → Cilium ENI Mode면 Pod IP가 VPC-native → 모든 문제가 해소
```

### 각 도출 단계가 기각한 대안

| 대안 | 기각 이유 |
|------|----------|
| CCM Route Controller 활성화 + providerID 패치 | overlay 유지 = 근본 미해결. AWS Route Table 50개 한도 |
| NLB Instance Mode 전환 | 2-hop latency, providerID도 여전히 필요 |
| ALB → Keycloak EC2 직접 타겟팅 | 임시 해결. Keycloak K8s 마이그레이션 시 제거 대상 |
| Calico Native Routing (BGP) | CNI 교체 필요 → 어차피 교체할 거면 Cilium이 상위호환 |

---

## 1. Executive Summary

RKE2 클러스터의 CNI를 **Canal(Flannel+Calico)에서 Cilium ENI Mode로 전환**한다.

이를 통해:

1. **Pod IP = VPC IP** → NLB/ALB IP-mode 네이티브 동작
2. **eBPF 기반 NetworkPolicy** → L3-L7 정책 (HTTP path 수준)
3. **kube-proxy 대체** → eBPF 기반 서비스 라우팅 (성능 향상)
4. **Hubble** → 실시간 네트워크 관측성
5. **불필요 컴포넌트 제거** → CCM Route Controller, kube-proxy

클러스터를 새로 구축하여 Cilium을 처음부터 포함시키는 **Clean Rebuild** 방식으로 진행한다.

---

## 2. 기술 배경 — 왜 Canal이 문제인가

### 현재 네트워크 스택

```
Canal (Flannel VXLAN + Calico Policy)
├── Pod-to-Pod: VXLAN 터널 (overlay)
├── Pod IP: 10.42.x.x (VPC에서 라우팅 불가)
├── NetworkPolicy: L3-L4 (Calico 기반)
├── Service Routing: kube-proxy (iptables)
└── 관측성: 없음
```

### Canal이 만든 문제 체인

```
VXLAN Overlay → Pod IP가 VPC에서 unreachable
  → NLB IP-mode Target Health 실패
  → ALBC가 등록한 Pod IP로 트래픽 도달 불가
  → CCM Route Controller로 우회해야 하나 비활성화 상태
  → providerID도 미설정 → CCM 자체가 미동작
```

**overlay 자체가 "비 VPC-native"이므로, 그 위에 쌓은 모든 AWS 통합이 무력화됨.**

---

## 3. Cilium 아키텍처

### Cilium ENI Mode 동작 원리

```
┌─────────────────────────────────────────────────┐
│ EC2 Instance (t3.large: 3 ENIs, 12 IPs/ENI)    │
│                                                  │
│  ENI-0 (Primary): 10.0.11.106 (Node IP)        │
│  ENI-1 (Cilium):  10.0.11.45, .46, .47, ...    │
│  ENI-2 (Cilium):  10.0.12.30, .31, .32, ...    │
│                                                  │
│  Pod-A: 10.0.11.45  ← VPC IP (직접 라우팅)      │
│  Pod-B: 10.0.12.30  ← VPC IP (직접 라우팅)      │
└─────────────────────────────────────────────────┘
```

- **IPAM**: Cilium이 AWS ENI API를 호출하여 Secondary IP 할당
- **결과**: Pod IP = VPC Subnet IP → NLB, ALB, EC2 어디서든 직접 접근 가능
- **overlay 없음**: VXLAN 캡슐화 없이 VPC 네이티브 라우팅

### 전환 전후 비교

| 영역 | Canal (Before) | Cilium (After) |
|------|---------------|----------------|
| **Pod IP** | 10.42.x.x (overlay) | 10.0.x.x (VPC-native) |
| **NLB IP-mode** | ❌ unreachable | ✅ 네이티브 |
| **CCM 의존성** | Route Controller 필수 | **불필요** |
| **providerID** | 필수 (미설정) | **불필요** |
| **NetworkPolicy** | L3-L4 (Calico) | L3-L7 (eBPF) |
| **kube-proxy** | iptables O(n) | eBPF O(1) |
| **Service Mesh** | 별도 설치 | 내장 (sidecar-free) |
| **관측성** | 없음 | Hubble |

---

## 4. Pod Density 분석

### t3.large ENI 한도

| 항목 | 값 |
|------|------|
| 최대 ENI 수 | 3 |
| IP/ENI | 12 |
| **기본 ENI mode** | `(3-1) × 12 = 24 pods/node` |
| **Prefix Delegation (/28)** | `(3-1) × (12 × 16) ≈ 240+ pods/node` |

### 판정

현재 DaemonSet(10+/node) + 앱 워크로드 감안 시:
- **기본 ENI**: 빠듯하지만 운영 가능 (24 pods)
- **Prefix Delegation**: 충분한 여유 (240+ pods)
- **권장**: `--aws-enable-prefix-delegation` 활성화

---

## 5. Clean Rebuild 전략

### 왜 Node-by-Node 마이그레이션이 아닌가

| 방식 | 장점 | 단점 |
|------|------|------|
| Node-by-Node | 점진적, 무중단 | 잔존 설정 오염, 복잡도 높음, dual-CIDR 관리 |
| **Clean Rebuild** | 깨끗한 상태, IaC 검증 | 다운타임 발생 |

**선택: Clean Rebuild** — 이유:
1. **GitOps 기반**: ArgoCD + Terraform으로 재현 가능한 인프라
2. **잔존 리스크 제거**: Canal iptables/VXLAN 설정 완전 제거
3. **IaC 자체 검증**: 플랫폼 재구축 능력 자체가 운영 성숙도 지표
4. **Keycloak K8s 마이그레이션 동시 진행**: 재구축 시점에 Keycloak도 K8s-native로 전환

### 재구축 순서

```
Phase 0: 기존 상태 백업
  - Vault unseal keys, Keycloak DB dump
  - ArgoCD app 매니페스트 확인 (Git SSOT)
  - Longhorn volume snapshots (S3 backup)

Phase 1: Terraform 코드 수정
  - rke2-cluster 모듈: cni=cilium, ENI mode, prefix delegation
  - CCM: Route Controller 관련 설정 정리
  - Keycloak: EC2 → K8s Helm Chart ArgoCD App 생성

Phase 2: 새 클러스터 프로비저닝
  - make init → make apply (50-rke2)
  - Cilium + eBPF kube-proxy replacement 확인
  - Hubble 활성화

Phase 3: ArgoCD 부트스트랩
  - 55-bootstrap apply
  - ArgoCD 앱 자동 sync (기존 매니페스트 재사용)
  - Keycloak K8s-native: Dual Ingress (Public OIDC + Internal Admin)

Phase 4: 데이터 복원 + 검증
  - Vault unseal + 기존 데이터 복원
  - Keycloak DB import
  - NLB Target Health 확인 (IP-mode ✅)
  - Hubble 네트워크 flow 검증

Phase 5: DNS 전환
  - Route53 레코드 → 새 NLB/ALB
  - 기존 클러스터 제거
```

---

## 6. Keycloak K8s 마이그레이션 (동시 진행)

Cilium 재구축 시점에 Keycloak도 글로벌 표준 패턴으로 전환:

### Target Architecture

```
K8s Namespace: keycloak
├── Deployment: keycloak (replicas: 2, HPA)
│   ├── KC_HOSTNAME: keycloak.dev.unifiedmeta.net
│   ├── KC_HOSTNAME_ADMIN: keycloak-admin.dev.unifiedmeta.net
│   └── KC_PROXY: edge
├── Public Ingress (nginx-public)
│   └── OIDC endpoint → /.well-known/*, /realms/*
├── Internal Ingress (nginx-internal)
│   └── Admin Console → /admin/*
├── CiliumNetworkPolicy
│   ├── Public: OIDC path만 허용 (L7)
│   └── Admin: internal ingress만 허용
├── Service → ClusterIP
└── DB: 기존 60-postgres (외부 EC2)
```

### 기존 EC2 Keycloak → K8s 전환 체크리스트

- [ ] Helm Chart 선정 (Bitnami or codecentric/keycloak)
- [ ] ArgoCD App 생성 (`gitops-apps/bootstrap/keycloak.yaml`)
- [ ] DB dump → K8s Pod에서 기존 RDS/EC2 DB 접속 설정
- [ ] `KC_HOSTNAME_ADMIN` 분리
- [ ] CiliumNetworkPolicy 적용
- [ ] 기존 `25-keycloak` Terraform stack → DB 전용으로 전환 또는 유지

---

## 7. 제거 대상 컴포넌트

| 컴포넌트 | 역할 | 대체 |
|---------|------|------|
| Canal (Flannel + Calico) | CNI | Cilium ENI Mode |
| kube-proxy | Service routing | Cilium eBPF |
| CCM Route Controller | VPC Route 관리 | 불필요 (ENI 직접) |
| `gitops-apps/keycloak-ingress/` | K8s 프록시 → EC2 | K8s-native Keycloak |
| `gitops-apps/bootstrap/keycloak-ingress.yaml` | ArgoCD App | K8s-native Keycloak App |

---

## 8. 리스크 및 완화 전략

| 리스크 | 영향 | 완화 |
|--------|------|------|
| VPC CIDR 소진 | Pod가 VPC IP 소비 | 서브넷 CIDR 용량 사전 계산 |
| Pod 밀도 제한 | t3.large: 기본 24 pods | Prefix Delegation 활성화 |
| 재구축 다운타임 | 전체 서비스 중단 | Blue-Green + DNS 전환 |
| Cilium 학습 곡선 | 운영 복잡도 | Hubble UI + 공식 문서 |
| EC2 ENI API Rate Limit | IP 할당 지연 | Warm pool 설정 (`--aws-instance-limit-mapping`) |
| Keycloak 데이터 마이그레이션 | 사용자/세션 유실 | DB dump/restore |

---

## 9. 관련 문서

| # | 문서 | 관계 |
|---|------|------|
| 07 | [cloud-provider-migration-report.md](07-cloud-provider-migration-report.md) | CCM 이슈 원점 |
| 08 | [nlb-architecture.md](08-nlb-architecture.md) | NLB 설계 원안 |
| 05 | [k8s-traffic-and-tls.md](05-k8s-traffic-and-tls.md) | Pod 네트워킹 기반 |
| 16 | [architecture-evolution-decision.md](16-architecture-evolution-decision.md) | 전체 아키텍처 고도화 문서 |
