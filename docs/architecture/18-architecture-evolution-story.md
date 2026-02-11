# 플랫폼 아키텍처 진화 스토리 — RKE2 채택부터 Cilium까지

**작성일**: 2026-02-09  
**용도**: 내부 세미나 / 기술 전파  
**대상**: 플랫폼 엔지니어, DevOps, 아키텍트

> 이 문서는 우리 플랫폼 인프라가 **왜 이런 구조가 되었는가**를 시간순으로 기술합니다.  
> 각 의사결정의 배경, 부딪힌 한계, 대안 검토, 최종 선택의 이유를 스토리 형태로 정리합니다.

---

## 목차

1. [왜 RKE2인가 — 출발점](#1-왜-rke2인가--출발점)
2. [초기 아키텍처의 한계 — Cloud Agnostic의 대가](#2-초기-아키텍처의-한계--cloud-agnostic의-대가)
3. [CCM 도입 결정 — K8s와 AWS를 연결하는 다리](#3-ccm-도입-결정--k8s와-aws를-연결하는-다리)
4. [CCM 도입의 난관 — 닭과 달걀 문제](#4-ccm-도입의-난관--닭과-달걀-문제)
5. [CCM의 구조적 문제 — "버그"의 진짜 원인](#5-ccm의-구조적-문제--버그의-진짜-원인)
6. [ALBC + IP Mode 시도 — 그리고 두 번째 벽](#6-albc--ip-mode-시도--그리고-두-번째-벽)
7. [Keycloak · Vault · Cilium — 근본 해결](#7-keycloak--vault--cilium--근본-해결)
8. [최종 아키텍처 — 3-Layer Identity Stack](#8-최종-아키텍처--3-layer-identity-stack)
9. [핵심 교훈](#9-핵심-교훈)
10. [글로벌 스탠다드 GAP 분석](#10-글로벌-스탠다드-gap-분석)
11. [고도화 로드맵 — 마일스톤별 Next Steps](#11-고도화-로드맵--마일스톤별-next-steps)
12. [제품 번들링 전략 — Standalone vs Enterprise](#12-제품-번들링-전략--standalone-vs-enterprise)

---

## 1. 왜 RKE2인가 — 출발점

우리 플랫폼은 **메타데이터 관리 및 거버넌스 솔루션**입니다.  
고객에게 직접 납품하는 제품이기 때문에, 인프라 설계의 **첫 번째 원칙**은 다음과 같았습니다:

> **"어떤 환경의 고객에게든 동일한 플랫폼을 배포할 수 있어야 한다."**

### EKS vs RKE2 판단

| 기준 | EKS | RKE2 |
|------|-----|------|
| AWS 고객 배포 | ✅ 즉시 가능 | ✅ 가능 |
| GCP/Azure 고객 배포 | ❌ 재구축 | ✅ 코드 변경 없음 |
| 온프렘/폐쇄망 배포 | ❌ 불가 | ✅ 가능 |
| 고객 납품 유연성 | AWS 전용 | **모든 고객** |
| 라이선스 | AWS 종속 | 오픈소스 |
| 운영 부담 | 낮음 | 높음 (학습 투자 필요) |

**결론**: CSP 독립성 + 납품 유연성이 핵심 → **RKE2 채택**

> 📎 상세: [14-future-roadmap.md](14-future-roadmap.md) §5

---

## 2. 초기 아키텍처의 한계 — Cloud Agnostic의 대가

### 초기 구성 (v0.2)

```
RKE2 v1.31 클러스터 (Control Plane 3 + Worker 4)
├── CNI: Canal (Flannel VXLAN + Calico NetworkPolicy)
├── Pod IP: 10.42.x.x (overlay 대역)
├── Ingress: nginx-ingress (NodePort)
├── Storage: Longhorn (CSP 독립 분산 스토리지)
├── GitOps: ArgoCD (App-of-Apps, Pure GitOps)
└── Cloud Provider: 없음 (순수 Kubernetes)
```

RKE2는 **"Cloud Agnostic"** — 어떤 클라우드에서든 동일하게 동작합니다.  
하지만 그 대가로, **AWS 위에서 실행해도 AWS 리소스를 자동으로 인식하지 못합니다.**

### CCM 도입 이전, 무엇이 동작했고 무엇이 안 되었는가

| 영역 | 동작 여부 | 상태 |
|------|----------|------|
| Pod 스케줄링 | ✅ | 정상 |
| Pod 간 통신 | ✅ | Canal VXLAN으로 동작 |
| Ingress Controller | ✅ | nginx-ingress 동작 |
| 분산 스토리지 | ✅ | Longhorn CSI |
| GitOps 배포 | ✅ | ArgoCD 정상 |
| **NLB 자동 생성** | ❌ | `Service(type: LoadBalancer)` 생성해도 **아무 일도 안 일어남** |
| **Node AWS 인식** | ❌ | K8s가 EC2의 Zone, Instance type 등 **모름** |
| **NLB Target 등록** | ❌ | 수동으로 Terraform + AWS CLI 사용 |

> **핵심 문제**: 외부 트래픽을 클러스터로 유입시키려면 NLB가 필요한데,  
> K8s가 AWS를 모르니 NLB를 자동으로 만들 수도, Target을 등록할 수도 없었다.

**💡 "K8s가 AWS를 모른다"는 게 무슨 뜻인가?**

Kubernetes 자체는 "NLB가 뭔지" 모릅니다. K8s가 아는 건 `Service(type: LoadBalancer)`라는 **추상적인 선언**뿐이고, 이걸 실제 AWS NLB로 만들어주는 건 별도의 컨트롤러입니다.

```
사용자가 Service(type: LoadBalancer) 생성
  │
  ├─ 컨트롤러(CCM)가 있을 때:
  │    CCM이 AWS API 호출 → NLB 생성 → TG에 Node 등록 → 트래픽 유입 ✅
  │
  └─ 컨트롤러가 없을 때 (우리의 상황):
       K8s는 "누군가 처리해주겠지" 하고 대기
       → 아무도 처리 안 함 → EXTERNAL-IP가 영원히 <pending> ❌
```

K8s는 **선언만 받고, 실행은 위임하는 구조**입니다. 위임받을 컨트롤러가 없으면 아무 일도 일어나지 않습니다. EKS에서는 이런 고민이 없는데, AWS가 CCM과 VPC CNI를 **기본 내장**해서 제공하기 때문입니다.

### 수동 운영의 고통

NLB를 Terraform으로 별도 생성하고, Worker Node를 **수동으로** Target Group에 등록해야 했습니다:

```
Terraform으로 NLB 생성 → AWS Console에서 수동 Target 등록
  → Worker Node 추가/제거 시마다 수동 TG 업데이트
    → 누락 시 서비스 중단
```

이것은 우리가 목표하는 **"Zero-Touch 프로비저닝"** 과 정면으로 충돌했습니다.

---

## 3. CCM 도입 결정 — K8s와 AWS를 연결하는 다리

### 아키텍처 방향과 CCM의 필요성

```
우리의 목표:
  Terraform IaC + GitOps(ArgoCD) + Zero-Touch 프로비저닝
  → 클러스터 생성 즉시 서비스 투입 가능한 완전 자동화
```

이 목표를 위해 반드시 필요한 것:
1. `Service(type: LoadBalancer)` → **NLB 자동 생성**
2. Worker Node → **Target Group 자동 등록**
3. Node 정보 → **AWS 메타데이터 자동 동기화**

이 세 가지를 제공하는 컴포넌트가 **Cloud Controller Manager(CCM)** 입니다.

**💡 CCM을 한마디로 표현하면?**

CCM은 **K8s와 클라우드 사이의 통역사**입니다. K8s는 "로드밸런서 만들어줘"라고 말할 줄만 알고, AWS는 "NLB를 만들려면 API 이렇게 호출해"라고 답할 줄만 압니다. 서로 다른 언어를 쓰는 두 시스템을 이어주는 것이 CCM의 역할입니다.

### CCM의 3가지 역할

```
┌─────────────────────────────────────────────────────────────┐
│              Cloud Controller Manager (CCM)                  │
│                                                              │
│  1. Node Controller                                          │
│     → EC2 메타데이터 → K8s Node 정보 동기화                  │
│     → Zone, Instance type, 종료 감지                         │
│                                                              │
│  2. Route Controller                                         │
│     → Pod 네트워크 경로를 VPC Route Table에 등록              │
│     → 다른 Node의 Pod이 통신할 수 있게 라우팅                │
│                                                              │
│  3. Service Controller                                       │
│     → Service(type: LB) 생성 시 NLB 자동 프로비저닝          │
│     → Worker Node를 Target Group에 자동 등록                 │
└─────────────────────────────────────────────────────────────┘
```

> **한 줄 요약**: CCM = **K8s가 AWS를 인식하고 AWS 리소스를 자동 관리할 수 있게 해주는 다리**

### 왜 In-tree가 아닌 External(Out-of-tree) CCM인가

과거에는 이 클라우드 연동 로직이 K8s 핵심 바이너리(`kube-controller-manager`) 안에 **내장(In-tree)** 되어 있었습니다.

**💡 비유하자면?**

```
과거 (In-tree) — "스마트폰에 모든 앱이 OS에 내장된 상태"
  kube-controller-manager 안에 AWS, GCP, Azure 코드가 모두 포함
  → 하나 고치려면 OS(K8s) 전체를 업데이트해야 함
  → 바이너리 비대화, 릴리즈 종속, 보안 리스크

현재 (Out-of-tree / External) — "앱스토어에서 개별 앱을 설치하는 상태"
  Cloud Controller Manager를 별도 Pod으로 분리 배포
  → AWS 연동만 독립적으로 업데이트 가능
  → 독립 업데이트, 경량 코어, 플러그인 아키텍처
```

Kubernetes는 단계적으로 In-tree Provider를 제거해 왔습니다:

- **v1.27**: In-tree Cloud Provider 사용 시 deprecation 경고 출력 (코드는 동작)
- **v1.29**: `--cloud-provider` 플래그에서 In-tree 옵션이 기본 비활성화, External CCM이 기본값으로 전환
- **v1.30~v1.31**: In-tree Provider 코드가 **완전히 제거(Removed)**

| | In-tree (v1.28 이하) | External CCM (v1.29+) |
|---|---|---|
| **위치** | kube-controller-manager 내장 | 별도 Pod으로 배포 |
| **설정** | `cloud-provider: "aws"` | `cloud-provider: "external"` |
| **Node 초기화** | 부팅 즉시 `Ready` | 부팅 시 `NotReady` + Taint → CCM이 초기화 |
| **업데이트** | K8s 전체 업그레이드 필요 | CCM만 독립 업데이트 |

> **우리의 상황**: RKE2 v1.31 → In-tree 코드 완전 제거됨 → **External CCM 설치가 선택이 아닌 필수**

---

## 4. CCM 도입의 난관 — 닭과 달걀 문제

External CCM 도입은 순탄하지 않았습니다.

### 난관 1: 순환 의존성 (Deadlock)

**💡 핵심 딜레마**: External CCM에서는 Node가 Ready가 되려면 CCM이 먼저 떠야 합니다. 그런데 CCM도 Pod이기 때문에 Ready인 Node가 있어야 스케줄링됩니다.

```
CCM Pod를 띄워야 → Node가 초기화(Ready)되는데
  → Node가 Ready가 아니면 → CCM Pod가 스케줄링 안 됨
    → 영원히 서로를 기다리는 교착 상태 (Deadlock)
```

이 문제는 EKS에서는 발생하지 않습니다. EKS는 CCM이 AWS 관리형 컨트롤 플레인에 내장되어 있어서, 사용자의 Node가 생성되기도 전에 이미 동작하고 있기 때문입니다.

**해결**: RKE2의 **Static Manifests** 기능 활용

일반적인 Pod은 API Server를 통해 스케줄링되지만, Static Manifest는 **파일 시스템에 YAML을 놓기만 하면** kubelet이 직접 Pod를 띄웁니다. API Server나 스케줄러에 의존하지 않으므로, Node가 NotReady여도 실행할 수 있습니다.

```
EC2 부팅 → UserData 실행
  → /var/lib/rancher/rke2/server/manifests/aws-ccm.yaml 배치
    → RKE2 엔진이 파일 시스템에서 자동 감지
      → CCM Pod 배포 (Toleration으로 uninitialized 노드에서도 실행)
        → Node 초기화 완료 → Ready
```

API 서버나 ArgoCD에 의존하지 않고, **부트스트랩 단계에서 CCM을 자동 주입**하여 교착 상태를 원천 차단했습니다.

> 📎 상세: [06-rke2-optimization-guide.md](06-rke2-optimization-guide.md)

### 난관 2: 엄격해진 식별자

External CCM은 과거 In-tree보다 **훨씬 엄격한 식별 체계**를 요구합니다:

- EC2 태그: `kubernetes.io/cluster/<name>=owned` 필수
- `providerID`: `aws:///ap-northeast-2a/i-0abc123...` 형식 필수
- 클러스터 이름: 인프라 태그와 CCM 인자가 **한 글자라도 다르면 동작 멈춤**

### 도입 결과

Static Manifests + Toleration + 태그 체계 정비로 CCM 도입 성공:

| 항목 | 결과 |
|------|------|
| Node Ready | ✅ 전체 노드 자동 초기화 |
| Taint 자동 제거 | ✅ `uninitialized` Taint 해소 |
| NLB 자동 생성 | ✅ `Service(type: LB)` → NLB 프로비저닝 |
| **NLB Target 등록** | ❌ **Worker Node를 Target Group에 등록하지 못함** |

> NLB는 만들어지는데, **Target이 비어있어서 트래픽이 도달하지 않는 상태.**

---

## 5. CCM의 구조적 문제 — "버그"의 진짜 원인

NLB Target 미등록 현상을 파고들면서, 이것이 단순한 소프트웨어 버그가 아닌 **구조적 비호환**임을 발견했습니다.

**💡 문제를 쉽게 이해하기 위한 배경**

NLB가 트래픽을 클러스터로 보내는 방식은 두 가지입니다:

```
방식 1: Instance Mode — "건물 정문으로 보내기"
  NLB → Worker Node(EC2)의 NodePort로 전송 → kube-proxy가 Pod에 전달
  전제조건: CCM이 "이 Node = 이 EC2 인스턴스"를 알아야 함 (providerID)

방식 2: IP Mode — "사람에게 직접 보내기"
  NLB → Pod IP로 직접 전송
  전제조건: Pod IP가 VPC 네트워크에서 실제로 도달 가능해야 함
```

우리 환경에서는 **두 방식 모두 작동하지 않았습니다.** 각각 다른 이유로:

### 문제 체인 (Root Cause Analysis)

NLB Target 미등록에는 **두 가지 독립적인 실패 경로**가 있었습니다:

```
실패 경로 A — Instance Mode (Worker:NodePort → TG 등록)
─────────────────────────────────────────────────────
  ③ providerID 미설정
     External CCM 모드에서 CCM Node Controller가 EC2 태그/권한 부족으로
     Node ↔ EC2 인스턴스 매핑 실패
       → NLB Target Group에 Worker 등록 불가

실패 경로 B — IP Mode (Pod IP → TG 직접 등록)
─────────────────────────────────────────────────────
  ① Canal VXLAN Overlay
     Pod IP가 10.42.x.x (overlay 대역) → VPC에서 라우팅 불가능

     ② CCM Route Controller 비활성화
        --configure-cloud-routes=false 상태
        → VPC Route Table에 Pod CIDR 우회 경로도 없음

       → Pod IP가 VPC unreachable → IP Mode 사용 불가
```

### 각 요인 상세

#### ① Canal VXLAN Overlay — 근본 원인

**💡 Overlay 네트워크란?**

실제 VPC 네트워크(10.0.x.x) 위에 **가상의 터널 네트워크(10.42.x.x)**를 덮어씌운 것입니다. Pod끼리는 이 터널을 통해 잘 통신하지만, 터널 바깥(AWS NLB, VPC 등)에서는 이 가상 IP를 알 수 없습니다.

비유하면, **사내 내선번호(10.42.x.x)**로는 사내 통화가 되지만, **외부(NLB)**에서 내선번호로 전화를 걸 수 없는 것**과 같습니다.

```
Canal CNI (Flannel 기반):
  Pod IP = 10.42.x.x   ← VXLAN 터널 안에서만 유효한 가상 IP (= 내선번호)
  VPC IP = 10.0.x.x    ← AWS VPC가 실제로 라우팅하는 IP (= 외부 전화번호)

  결과: NLB가 Pod IP(10.42.x.x)로 트래픽을 보내면 → VPC에서 DROP
        → NLB Target Health: unhealthy
```

**overlay 자체가 "비 VPC-native"이므로, 그 위에 쌓은 모든 AWS 통합이 무력화됩니다.**

#### ② CCM Route Controller 비활성화

overlay 환경에서도 CCM Route Controller가 VPC Route Table에 `10.42.x.x/24 → Node` 경로를 만들어주면 우회할 수 있습니다. 이는 "내선번호(10.42.x.x)로 전화가 오면 이 건물(Node)로 연결해줘"라는 안내판을 VPC에 설치하는 것과 같습니다. 그러나:

- `--configure-cloud-routes=false`로 설정 → Route를 **아예 만들지 않음** (안내판 자체가 없음)
- 설령 활성화해도 **AWS VPC Route Table 50개 Route 한도** → Node가 많아지면 한도 초과 → 근본 해결이 아님

#### ③ providerID 미설정 — Instance Mode조차 실패시킨 독립적 원인

CCM이 K8s Node 객체와 EC2 인스턴스를 매핑하려면 `providerID`가 필요합니다:

```
Expected: spec.providerID: aws:///ap-northeast-2a/i-0abc123def456
Actual:   spec.providerID: (없음)
```

External CCM 모드(`--cloud-provider=external`)에서는 kubelet이 providerID를 설정하지 않는 것이 **정상 동작**입니다. providerID 설정은 **CCM Node Controller의 책임**이며, CCM이 EC2 태그(예: `kubernetes.io/cluster/<name>=owned`)나 IAM 권한이 불완전하면 매핑에 실패합니다.

> **주의**: 이 문제는 ①②의 overlay 문제와는 **독립적**입니다. overlay를 해결하더라도 providerID가 없으면 Instance Mode(NodePort 방식)에서도 Target 등록이 실패합니다.

### "버그"가 아니라 "구조적 비호환"

**두 가지 독립적인 실패 경로**가 동시에 존재했습니다:

| 실패 경로 | 요인 | 영향 |
|-----------|------|------|
| **Instance Mode 실패** | ③ providerID 미설정 (CCM의 태그/권한 매핑 실패) | CCM이 Node ↔ EC2 매핑 불가 → TG에 Worker 등록 불가 |
| **IP Mode 실패** | ① Canal overlay (Pod IP가 VPC unreachable) + ② Route Controller 비활성 (우회 경로도 없음) | NLB가 Pod IP로 트래픽 전달 불가 |
| **종합** | **RKE2 + Canal + External CCM** 조합에서 **두 모드 모두 동작하지 않는** 구조적 한계 |

> 📎 상세: [07-cloud-provider-migration-report.md](07-cloud-provider-migration-report.md), [08-nlb-architecture.md](08-nlb-architecture.md)

---

## 6. ALBC + IP Mode 시도 — 그리고 두 번째 벽

CCM의 LoadBalancer 기능이 제대로 동작하지 않으므로, **전용 로드밸런서 컨트롤러인 ALBC(AWS Load Balancer Controller)** 를 도입하기로 했습니다.

**💡 CCM vs ALBC — 왜 전용 컨트롤러가 필요한가?**

CCM은 "만능 통역사"입니다. Node 관리, 라우팅, 로드밸런서를 모두 다루지만, 그만큼 각 기능이 깊지 않습니다. 특히 로드밸런서 관련해서 CCM은 **Instance Mode(Worker Node 단위)**만 지원합니다.

ALBC는 "로드밸런서 전문가"입니다. 로드밸런서만 다루되, **IP Mode(Pod 단위 직접 연결)**까지 지원하여 더 효율적인 트래픽 라우팅이 가능합니다.

### CCM vs ALBC 비교

| 항목 | CCM (현재) | ALBC (목표) |
|------|-----------|------------|
| Target 유형 | **Instance** (Worker:NodePort) | **IP** (Pod 직접) |
| 트래픽 경로 | NLB → Worker → kube-proxy → Pod (2-hop) | NLB → **Pod 직접** (1-hop) |
| Target 등록 | Worker Node 고정 (수동) | **Pod 자동 증감** |
| NodePort | 필요 (30000-32767) | 불필요 |
| Worker 추가 시 | 수동 TG 업데이트 ⚠️ | **자동** |

### 차단 ①: IRSA가 없다

ALBC Pod가 AWS API(NLB/ALB 관리)를 호출하려면 **IAM 인증**이 필요합니다.  
EKS에서는 IRSA(IAM Roles for Service Accounts)가 자동으로 제공되지만:

**💡 IRSA란?**

Pod가 AWS 리소스를 사용하려면 "나는 이 권한을 가진 Pod이야"라고 AWS에 증명해야 합니다. 이때 필요한 것이 **신뢰할 수 있는 신원 보증 기관(OIDC Provider)**입니다. IRSA의 흐름은 다음과 같습니다:

```
EKS:
  Pod가 "나 ALBC야" → EKS OIDC Provider가 "맞아, 이 Pod은 진짜야" (신원 보증)
    → AWS STS가 "확인, 임시 자격증명 줄게" → ALBC가 NLB 관리 ✅

RKE2:
  Pod가 "나 ALBC야" → OIDC Provider ???  → 신원을 보증해줄 기관이 없음
    → AWS STS: "누군지 모르니 거부" → ALBC가 AWS API 호출 불가 ❌
```

**RKE2에는 OIDC Provider가 없습니다.** EKS는 클러스터 생성 시 OIDC Provider가 자동으로 만들어지지만, RKE2는 CSP 독립적이므로 이런 AWS 전용 기능이 포함되어 있지 않습니다.

### 차단 ②: Overlay로 IP Mode 불가

ALBC의 핵심 장점인 **IP Mode** — NLB가 Pod IP로 직접 트래픽을 전송:

```
IP Mode 전제조건: Pod IP가 VPC에서 라우팅 가능해야 함

현실:
  Canal Pod IP = 10.42.x.x (overlay) → VPC에서 unreachable
  → IP Mode로 전환해도 NLB Target Health = unhealthy
  → 근본적으로 불가능
```

> **두 개의 벽**: OIDC Provider 부재 + overlay networking  
> 이 시점에서 **패치가 아닌 플랫폼 수준의 재설계**가 필요함을 인식했습니다.

---

## 7. Keycloak · Vault · Cilium — 근본 해결

각 차단 요소를 해결하는 과정에서 **의사결정이 연쇄적으로 이어졌습니다.**

### 의사결정 체인

**💡 하나의 문제를 해결하려다 보니, 도미노처럼 연쇄적으로 결정이 이어졌습니다.**

```
CCM 버그 → NLB를 어떻게 고치지?
  → ALBC 도입하자
    → ALBC에 IAM 인증이 필요한데 RKE2엔 IRSA가 없다
      → Pod에게 AWS 자격증명을 줄 방법이 필요하다

        → Keycloak이면 SSO도 되고 OIDC Provider도 된다
          → Keycloak 도입 결정 ✅ (사람의 인증 해결)

            → 그런데 Workload Identity(Pod 인증)는 Keycloak OIDC로 안 된다
              → Vault AWS Secrets Engine이면?
                → K8s SA Token → Vault K8s Auth → AWS SE → STS 임시 자격증명
                  → Vault 도입 결정 ✅ (Pod의 인증 해결)

                    → NLB IP-mode는 왜 안 되지?
                      → Pod IP가 10.42.x.x (overlay) → VPC unreachable
                        → 근본 원인: Canal VXLAN overlay (내선번호 문제)
                          → Cilium ENI Mode로 전환 결정 ✅ (네트워크 근본 해결)
```

### 각 컴포넌트가 해소하는 것

#### Keycloak — OIDC Provider + SSO 통합 (차단 ① 해소)

| 문제 | Before | After |
|------|--------|-------|
| OIDC Provider 부재 | RKE2에 없음 | ✅ Keycloak이 OIDC Provider |
| 서비스별 개별 로그인 | 6개 서비스 × 개별 계정 | ✅ 한 번 로그인으로 전체 접근 (SSO) |
| 퇴사자 접근 차단 | 서비스마다 개별 비활성화 | ✅ Keycloak에서 한 번에 차단 |
| K8s API 접근 | kubeconfig 토큰 (영구) | ✅ OIDC 기반 임시 토큰 |
| 고객 멀티테넌트 | 미구현 | ✅ Realm 기반 테넌트 분리 |

> 📎 상세: [11-keycloak-idp-strategy.md](11-keycloak-idp-strategy.md)

#### Vault AWS Secrets Engine — Workload Identity (IRSA 대체)

ALBC Pod의 IAM 인증을 Keycloak OIDC가 아닌 **Vault**가 담당합니다.

**💡 왜 Keycloak으로 IRSA를 대체하지 않는가?**

Keycloak은 **사람(Human)의 신원을 증명**하는 데 최적화되어 있습니다. 브라우저 로그인, SSO, MFA 등이 그 영역입니다. 반면 IRSA가 하는 일은 **Pod(Machine)에게 AWS 임시 자격증명을 발급**하는 것입니다.

Pod는 브라우저로 로그인할 수 없고, AWS STS는 Keycloak을 신뢰하도록 설정되어 있지 않습니다. 따라서 Pod → AWS 자격증명 경로에는 **Vault**라는 별도의 중개자가 필요합니다.

```
사람의 인증: Keycloak (브라우저 SSO, OIDC 토큰)
Pod의 인증:  Vault    (K8s SA Token → AWS STS 임시 자격증명)
```

구체적인 흐름:

```
ALBC Pod → K8s ServiceAccount Token (Pod의 신분증)
  → Vault (K8s Auth Method로 "이 Pod이 진짜 ALBC 맞는지" 검증)
    → Vault AWS Secrets Engine (AssumeRole)
      → STS 임시 자격증명 발급 (15분 TTL, 자동 rotation)
        → ALBC가 NLB/ALB Target Group 관리
```

| 항목 | IRSA (EKS 방식) | Vault AWS SE (우리 방식) |
|------|----------------|------------------------|
| OIDC Provider | EKS 자동 | 불필요 (Vault K8s Auth) |
| 자격증명 수명 | **1시간** (기본, 최대 12시간) | **15분** (더 안전) |
| CSP 종속 | AWS 전용 | **CSP 무관** (GCP, Azure 확장 가능) |
| 기존 인프라 | 신규 구축 | ✅ Vault + K8s Auth 재활용 |

#### Cilium ENI Mode — VPC-native Pod IP (차단 ② 해소)

**💡 Canal → Cilium 전환을 한마디로 표현하면?**

Canal은 Pod에게 **내선번호(10.42.x.x)**를 부여했습니다. 사내 통화는 되지만 외부에서 직접 전화할 수 없었죠. Cilium ENI Mode는 Pod에게 **외부 전화번호(10.0.x.x)**를 직접 부여합니다. AWS VPC에서 직접 라우팅되는 진짜 IP이므로, NLB든 다른 EC2든 어디서든 직접 접근할 수 있습니다.

```
Canal (Before) — 가상 IP (내선번호):
  Pod IP = 10.42.x.x (VXLAN overlay)
  → VPC에서 라우팅 불가 → NLB IP-mode 불가

Cilium ENI Mode (After) — 실제 VPC IP (외부 전화번호):
  Pod IP = 10.0.x.x (VPC Subnet IP)
  → VPC에서 직접 라우팅 → NLB IP-mode 네이티브 동작
```

**어떻게 가능한가?** Cilium은 AWS ENI(Elastic Network Interface)의 Secondary IP를 Pod에 할당합니다. EC2 인스턴스에 추가 네트워크 카드(ENI)를 꽂고, 그 카드에 할당된 IP를 각 Pod에게 하나씩 나눠주는 방식입니다:

```
┌─────────────────────────────────────────────────────┐
│ EC2 Instance (t3.large)                             │
│                                                      │
│  ENI-0 (Primary): 10.0.11.106 (Node IP)             │
│  ENI-1 (Cilium):  10.0.11.45, .46, .47, ...         │
│  ENI-2 (Cilium):  10.0.12.30, .31, .32, ...         │
│                                                      │
│  Pod-A: 10.0.11.45  ← VPC IP (직접 라우팅 가능!)     │
│  Pod-B: 10.0.12.30  ← VPC IP (직접 라우팅 가능!)     │
└─────────────────────────────────────────────────────┘
```

overlay가 아닌 VPC-native IP이므로 **NLB, ALB, EC2 어디서든 직접 접근 가능**.

| 영역 | Canal (Before) | Cilium ENI (After) |
|------|---------------|-------------------|
| **Pod IP** | 10.42.x.x (overlay) | 10.0.x.x (VPC-native) |
| **NLB IP-mode** | ❌ unreachable | ✅ 네이티브 |
| **CCM 의존성** | Route Controller 필요 | **불필요** |
| **NetworkPolicy** | L3-L4 (Calico) | L3-**L7** (eBPF, HTTP path 수준) |
| **kube-proxy** | iptables (규칙 수에 비례하여 갱신 지연) | eBPF (hash map 기반 O(1) 조회) |
| **네트워크 관측성** | 없음 | Hubble (실시간 flow) |

> Cilium 전환은 Canal overlay가 만든 **근본적인 문제 체인**(NLB Target unhealthy, CCM Route 미동작, ALBC IP-mode 불가)을 **일괄 해소**합니다.

> 📎 상세: [17-cilium-cni-architecture.md](17-cilium-cni-architecture.md)

---

## 8. 최종 아키텍처 — 3-Layer Identity Stack

모든 의사결정을 거쳐 도달한 최종 아키텍처:

```
┌──────────────────────────────────────────────────────────┐
│                   3-Layer Identity Stack                   │
│                                                           │
│  ┌────────────────┐ ┌──────────────┐ ┌─────────────────┐ │
│  │   Keycloak      │ │    Vault     │ │    Teleport     │ │
│  │ L1: Human SSO   │ │ L2: Secrets  │ │ L3: Access      │ │
│  │                  │ │ + Workload   │ │                 │ │
│  │ 5개 서비스 SSO   │ │   Identity   │ │ SSH, K8s, DB    │ │
│  │ K8s OIDC Auth   │ │ 동적 시크릿  │ │ Web App         │ │
│  │                  │ │ AWS SE(STS)  │ │ 세션 녹화       │ │
│  └───────┬────────┘ └──────┬───────┘ └───────┬─────────┘ │
│          │                  │                  │           │
│          ▼                  ▼                  ▼           │
│  ┌────────────────────────────────────────────────────┐   │
│  │           Kubernetes Platform (RKE2)                │   │
│  │  Cilium ENI · ALBC · nginx-ingress · ArgoCD        │   │
│  │  cert-manager · external-dns · Longhorn · Hubble   │   │
│  └────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘
```

### 버전별 진화 요약

```
v0.1 (Foundation):
  VPC ── Golden Image ── Bastion ── Harbor
  "인프라 뼈대 완성. K8s 없음."

v0.2 (K8s Core):
  + RKE2 ── ArgoCD ── Longhorn ── nginx-ingress
  "K8s + GitOps 동작. NLB 수동, 서비스 없음."

v0.3 (Services):
  + Teleport ── PostgreSQL ── Neo4j ── OpenSearch ── Grafana
  "서비스 전부 배포. 개별 인증, 시크릿 하드코딩."

v0.4 (Zero-Trust):
  + Dual NLB ── Dual Ingress ── DNS-01 ── WAF
  "트래픽 분리, Zero-Trust 접근. 인증/시크릿 미해결."

v0.5 (Identity & Secrets):
  + Keycloak (SSO) ── Vault (동적 시크릿) ── ALBC (IP mode)
  "3-Layer Identity Stack 완성. 업계 표준 달성."

v1.0 (Network Evolution):
  + Cilium ENI ── eBPF kube-proxy ── Hubble ── L7 NetworkPolicy
  "VPC-native Pod IP. 모든 네트워크 문제 근본 해소."
```

> 📎 상세: [16-architecture-evolution-decision.md](16-architecture-evolution-decision.md)

---

## 9. 핵심 교훈

### ① 하나의 문제가 아키텍처 전체를 바꿀 수 있다

CCM의 NLB Target 미등록이라는 **하나의 증상**을 추적한 결과:
- CNI 교체 (Canal → Cilium)
- IdP 도입 (Keycloak)
- 시크릿 관리 도입 (Vault)
- 로드밸런서 컨트롤러 교체 (CCM → ALBC)

4개 영역의 근본적 재설계로 이어졌습니다.

### ② "왜?"를 5번 물어야 근본 원인이 나온다

```
[Instance Mode 경로]
왜 NLB Target이 등록 안 되지?     → CCM이 Worker를 TG에 넣지 못함
왜 CCM이 안 동작하지?             → providerID 미설정
왜 providerID가 없지?             → CCM Node Controller가 EC2 태그/권한 부족으로 매핑 실패

[IP Mode 경로]
왜 IP-mode가 안 되지?             → Pod IP가 VPC unreachable
왜 Pod IP가 unreachable이지?      → Canal VXLAN overlay ← 근본 원인
```

### ③ Cloud Agnostic은 공짜가 아니다

RKE2의 CSP 독립성은 **멀티클라우드/온프렘 납품**이라는 비즈니스 가치를 제공하지만,  
EKS가 자동으로 해주는 것들(OIDC, IRSA, NLB 관리)을 **직접 구축해야 하는 비용**이 있습니다.

**💡 비유하면**: EKS는 **풀옵션 아파트**(입주 즉시 생활 가능하지만, 그 단지에서만 살 수 있음)이고, RKE2는 **빈 땅**(전기·수도·가스를 직접 끌어와야 하지만, 어디에든 지을 수 있음)입니다.

| EKS가 자동으로 해주는 것 | 우리가 직접 구축한 것 | 비유 |
|------------------------|------------------------|------|
| OIDC Provider | Keycloak | 신원 보증 기관 |
| IRSA (Pod IAM) | Vault AWS Secrets Engine | Pod용 신분증 발급기 |
| VPC CNI (IP Mode) | Cilium ENI Mode | 외부 전화번호 부여 |
| NLB 자동 관리 | ALBC | 로드밸런서 전문가 |

> **하지만 그 결과**: EKS보다 **더 유연하고, 더 안전하며, CSP에 종속되지 않는** 아키텍처를 갖게 되었습니다.

### ④ 시장이 검증한 아키텍처

우리 목표 아키텍처가 오버스펙이 아님을 시장이 증명합니다:

| 솔루션 | IdP | Secrets | 비고 |
|--------|-----|---------|------|
| **Atlan** (시장 선두) | **Keycloak** ★ | **Vault** ★ | 우리와 동일 구성 |
| Collibra | SSO | **Vault** | |
| Alation | SAML | **Vault** | |
| DataHub (오픈소스) | **OIDC (Keycloak)** | K8s Secrets | |

> 📎 상세: [market-player-infrastructure-research.md](market-player-infrastructure-research.md)

---

## 10. 글로벌 스탠다드 GAP 분석

현재 우리 아키텍처(v1.0)를 **CNCF 플랫폼 엔지니어링 성숙도 모델(2025)**과 글로벌 시장 선두 업체(Atlan, Collibra 등)의 인프라 스택과 비교합니다.

### 현재 위치 — 글로벌 기준으로 어디에 있는가

```
CNCF Platform Maturity Model (5단계)

  Level 1: Provisional   ← 우리의 v0.1~v0.2 (수동 운영, 개별 도구)
  Level 2: Operational   ← 우리의 v0.3~v0.4 (서비스 배포, 수동 인증/시크릿)
  Level 3: Scalable      ← ★ 우리의 현재 위치 (v1.0)
  Level 4: Optimizing    ← 다음 목표 (자동화 고도화, 셀프서비스, 관측성)
  Level 5: Innovating    ← 장기 목표 (AI Ops, 자율 운영)
```

**💡 Level 3 (Scalable)에 도달한 근거:**
우리는 GitOps(ArgoCD), IaC(Terraform), Identity Stack(Keycloak + Vault + Teleport), VPC-native CNI(Cilium)를 갖추고 있습니다. 이는 CNCF 기준으로 **표준화된 플랫폼 운영**에 해당합니다.

### 영역별 GAP 상세

| 영역 | 글로벌 스탠다드 (Level 4~5) | 우리 현재 (v1.0) | GAP |
|------|---------------------------|-----------------|-----|
| **Observability** | OpenTelemetry + LGTM Stack (Loki/Grafana/Tempo/Mimir), 3 Pillars(Metrics/Logs/Traces) 통합 | Grafana + 부분적 메트릭 수집 | 🔴 **Traces/Logs 파이프라인 부재** |
| **Developer Portal** | Backstage(CNCF) 기반 IDP, 셀프서비스 인프라 프로비저닝 | 없음 (CLI/kubectl 직접 사용) | 🔴 **개발자 셀프서비스 부재** |
| **FinOps** | Kubecost/OpenCost 기반 비용 가시성, 팀별 차지백 | 없음 (AWS 빌링만 사용) | 🟡 비용 최적화 도구 부재 |
| **Policy as Code** | OPA/Kyverno 기반 자동 정책 검증, Admission Control | 수동 리뷰 | 🟡 자동 정책 집행 부재 |
| **Chaos Engineering** | LitmusChaos/Chaos Mesh 기반 회복력 검증 | 없음 | 🟡 장애 시뮬레이션 부재 |
| **CI/CD** | Tekton/GitHub Actions + 이미지 서명(Sigstore/cosign) | Harbor + 기본 CI | 🟡 Supply Chain Security 미흡 |
| **Multi-Tenancy** | Namespace 격리 + NetworkPolicy + ResourceQuota + RBAC | Keycloak Realm 수준 | 🟡 K8s 리소스 수준 격리 미흡 |
| **AI Ops** | AI Agent 기반 이상 탐지, 자동 스케일링 추천, 로그 분석 | 없음 | ⚪ 장기 과제 |
| **Identity** | OIDC SSO + Vault + Zero-Trust Access | Keycloak + Vault + Teleport | ✅ **글로벌 수준 달성** |
| **Networking** | VPC-native CNI + eBPF + L7 Policy + Service Mesh (선택) | Cilium ENI + Hubble | ✅ **글로벌 수준 달성** |
| **GitOps** | ArgoCD/Flux + App-of-Apps + Multi-cluster | ArgoCD App-of-Apps | ✅ **글로벌 수준 달성** |
| **Secret Management** | 동적 시크릿 + 자동 rotation + CSP 무관 | Vault AWS SE + K8s Auth | ✅ **글로벌 수준 달성** |

### 시장 선두 업체 인프라 비교

글로벌 데이터 거버넌스 플랫폼 중 우리와 유사한 제품의 인프라 스택을 비교합니다:

| 영역 | Atlan (시장 선두) | Collibra (엔터프라이즈) | **우리 (v1.0)** |
|------|------------------|----------------------|----------------|
| Orchestration | Kubernetes (cloud-native) | Kubernetes | ✅ RKE2 (K8s) |
| IdP / SSO | Keycloak | Enterprise SSO | ✅ Keycloak |
| Secrets | Vault | Vault | ✅ Vault |
| Observability | Full-stack (OTel) | Enterprise APM | 🔴 **부분적** |
| Developer Portal | 내부 IDP | 내부 도구 | 🔴 **없음** |
| Multi-Tenancy | Namespace + RBAC | 고객별 격리 | 🟡 Realm 수준 |
| CSP 독립성 | SaaS (AWS 기반) | Multi-cloud SaaS | ✅ **CSP 무관** |

> **핵심 인사이트**: Identity/Secrets/Networking은 이미 글로벌 수준입니다. 다음 고도화의 핵심은 **Observability**, **Developer Portal(IDP)**, **FinOps** 세 영역입니다.

---

## 11. 고도화 로드맵 — 마일스톤별 Next Steps

### 전체 마일스톤 개요

```
현재 (v1.0)                                                    장기 목표 (v3.0)
    │                                                                │
    ▼                                                                ▼
┌─────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  v1.0   │───▶│  v1.5    │───▶│  v2.0    │───▶│  v2.5    │───▶│  v3.0    │
│ Network │    │Observa-  │    │Developer │    │ Multi-   │    │AI Ops &  │
│Evolution│    │bility    │    │Platform  │    │ Tenant   │    │Self-Heal │
│ ✅ Done │    │Stack     │    │(IDP)     │    │ & FinOps │    │          │
└─────────┘    └──────────┘    └──────────┘    └──────────┘    └──────────┘
                  Q2 2026         Q3 2026        Q4 2026       2027 H1
               CNCF Level 3+   CNCF Level 4   CNCF Level 4   CNCF Level 5
```

### v1.5 — Observability Stack (Q2 2026)

**💡 왜 지금 Observability인가?**

현재 장애 발생 시 "어디서 문제가 생겼는지" 파악하기 위해 kubectl logs, Grafana 대시보드, AWS Console을 오가며 수동 추적해야 합니다. 서비스가 늘어날수록 이 방식은 한계에 도달합니다. CNCF 2025 보고서에 따르면, 플랫폼 팀의 84%가 Observability 비용과 복잡성에 어려움을 겪고 있으며, OpenTelemetry가 그 해법으로 부상하고 있습니다.

```
목표: 장애 발생 시 "무엇이, 어디서, 왜" 발생했는지를 1분 안에 파악

도입 스택:
  ┌──────────────────────────────────────────────────────────┐
  │              Observability Stack (LGTM)                    │
  │                                                            │
  │  ┌──────────────┐  ┌──────────┐  ┌──────────────────────┐ │
  │  │ OpenTelemetry │  │ Grafana  │  │ Alerting & On-Call   │ │
  │  │ Collector     │  │ (통합 UI)│  │ (Grafana Alerting)   │ │
  │  └──────┬───────┘  └────┬─────┘  └──────────────────────┘ │
  │         │               │                                   │
  │  ┌──────▼───┐  ┌───────▼──┐  ┌────────────┐               │
  │  │  Mimir   │  │   Loki   │  │   Tempo    │               │
  │  │ (Metrics)│  │  (Logs)  │  │  (Traces)  │               │
  │  └──────────┘  └──────────┘  └────────────┘               │
  │                                                            │
  │  + Hubble (Cilium 네트워크 flow, 이미 보유)                │
  └──────────────────────────────────────────────────────────┘
```

| 작업 항목 | 설명 | 우선순위 |
|-----------|------|---------|
| OTel Collector 배포 | DaemonSet으로 전 노드 텔레메트리 수집 | P0 |
| Loki 도입 | 로그 중앙 집중화, 구조화된 로그 파이프라인 | P0 |
| Tempo 도입 | 분산 트레이싱, 서비스 간 요청 추적 | P0 |
| Mimir 도입 | 장기 메트릭 스토리지 (Prometheus 호환) | P1 |
| Grafana 통합 대시보드 | Metrics ↔ Logs ↔ Traces 상호 연결 (Exemplar) | P1 |
| Alert Rule 표준화 | SLO 기반 알림 체계 수립 | P1 |

**완료 기준**: 임의의 API 요청에 대해 "어떤 Pod에서 처리했고, 어떤 DB 쿼리가 느렸는지"를 Grafana 한 화면에서 추적 가능

### v2.0 — Developer Platform / IDP (Q3 2026)

**💡 왜 IDP가 필요한가?**

Gartner는 2026년까지 소프트웨어 엔지니어링 조직의 80%가 플랫폼 팀을 갖출 것으로 전망하며, CNCF는 2025년 Backstage의 기여자 수가 전년 대비 2배 이상 증가했다고 보고합니다. 개발자가 인프라를 직접 요청하고 기다리는 구조에서, **셀프서비스로 즉시 프로비저닝**하는 구조로 전환해야 합니다.

```
목표: 개발자가 kubectl 없이도 서비스 배포, 환경 생성, 문서 조회 가능

도입 스택:
  ┌──────────────────────────────────────────────────────┐
  │             Backstage (CNCF IDP Framework)             │
  │                                                        │
  │  Software Catalog    → 모든 서비스/API/인프라 목록      │
  │  Software Templates  → 새 서비스 원클릭 생성            │
  │  TechDocs            → 마크다운 기반 문서 자동 발행     │
  │  Plugins             → ArgoCD, Vault, Grafana 통합     │
  │                                                        │
  │  ┌──────────────────────────────────────────────────┐  │
  │  │  Keycloak SSO → Backstage 로그인 통합             │  │
  │  │  ArgoCD Plugin → 배포 상태 실시간 확인            │  │
  │  │  Grafana Plugin → 서비스별 대시보드 인라인 조회   │  │
  │  │  Vault Plugin → 시크릿 관리 셀프서비스            │  │
  │  └──────────────────────────────────────────────────┘  │
  └──────────────────────────────────────────────────────┘
```

| 작업 항목 | 설명 | 우선순위 |
|-----------|------|---------|
| Backstage 코어 배포 | K8s 위에 Backstage 인스턴스 배포, Keycloak SSO 연동 | P0 |
| Software Catalog 구축 | 기존 서비스/DB/인프라를 카탈로그에 등록 | P0 |
| Software Templates | 새 마이크로서비스 생성 템플릿 (CI/CD 파이프라인 포함) | P1 |
| TechDocs 연동 | 기존 마크다운 문서를 Backstage에서 자동 발행 | P1 |
| ArgoCD / Grafana Plugin | 배포 상태, 메트릭을 Backstage 내에서 확인 | P2 |

**완료 기준**: 신규 개발자가 "새 서비스 만들기" 버튼 하나로 Git repo + CI/CD + K8s namespace + 모니터링까지 자동 생성

### v2.5 — Multi-Tenancy & FinOps (Q4 2026)

**💡 왜 Multi-Tenancy와 FinOps를 같이 진행하는가?**

고객 납품 시 "이 고객의 워크로드가 다른 고객에게 영향을 주면 안 됨(격리)"과 "이 고객에게 들어가는 인프라 비용을 정확히 산출해야 함(비용 가시성)"은 동전의 양면입니다.

```
목표: 고객별 워크로드 격리 + 팀/고객별 인프라 비용 가시성

Multi-Tenancy 강화:
  ┌─────────────────────────────────────────────────────────┐
  │  Keycloak Realm (이미 보유)                               │
  │    + K8s Namespace 격리 (Namespace-per-tenant)            │
  │      + Cilium L7 NetworkPolicy (테넌트 간 트래픽 차단)    │
  │        + ResourceQuota / LimitRange (리소스 상한)          │
  │          + Kyverno Policy (정책 자동 집행)                 │
  └─────────────────────────────────────────────────────────┘

FinOps:
  ┌─────────────────────────────────────────────────────────┐
  │  OpenCost (CNCF) or Kubecost                              │
  │    → Namespace/Label 기반 비용 분배                        │
  │    → Grafana 대시보드 연동 (팀별/고객별 비용 시각화)       │
  │    → 유휴 리소스 탐지 + 최적화 권고                       │
  └─────────────────────────────────────────────────────────┘
```

| 작업 항목 | 설명 | 우선순위 |
|-----------|------|---------|
| Namespace-per-tenant 설계 | 고객별 네임스페이스 자동 생성 + RBAC | P0 |
| Kyverno 도입 | Policy as Code: 이미지 출처 검증, 리소스 제한 자동 적용 | P0 |
| Cilium L7 정책 강화 | 테넌트 간 HTTP path 수준 접근 제어 | P1 |
| OpenCost / Kubecost 배포 | K8s 리소스 비용 메트릭 수집 | P1 |
| 비용 대시보드 | Grafana에 팀/고객별 비용 시각화 | P2 |

**완료 기준**: 고객 A의 Pod가 고객 B의 네임스페이스에 접근 불가 + 고객별 월간 인프라 비용을 자동 리포트

### v3.0 — AI Ops & Self-Healing (2027 H1)

**💡 이 단계는 왜 마지막인가?**

AI Ops는 "쌓여 있는 데이터"가 있어야 의미가 있습니다. v1.5에서 Observability 데이터가 쌓이고, v2.0에서 서비스 카탈로그가 구축되고, v2.5에서 비용/정책 데이터가 갖춰진 후에야 AI가 활용할 맥락이 완성됩니다. CNCF 2026년 전망에서도 AI Agent가 플랫폼 엔지니어링의 핵심으로 부상하되, "성숙한 플랫폼 위에서만 AI가 효과를 발휘한다"고 강조합니다.

```
목표: AI 기반 이상 탐지, 자동 스케일링 추천, 장애 자동 복구

도입 영역:
  ┌──────────────────────────────────────────────────────────┐
  │  AIOps Layer                                               │
  │                                                            │
  │  이상 탐지     → OTel 메트릭 기반 ML 모델                  │
  │  자동 스케일링 → KEDA + 예측 기반 스케일링 추천             │
  │  자동 복구     → Argo Rollouts + Chaos Mesh 기반 회복력    │
  │  LLM 로그 분석 → 로그 요약 및 RCA(근본 원인 분석) 자동화  │
  │  FinOps AI     → 비용 이상 탐지 + 최적화 자동 추천         │
  └──────────────────────────────────────────────────────────┘
```

---

## 12. 제품 번들링 전략 — Standalone vs Enterprise

### 💡 왜 번들링을 고려하는가?

현재 우리 플랫폼은 **모든 컴포넌트를 풀셋으로 배포**합니다. 그러나 모든 고객이 Vault, Teleport, Cilium을 다 필요로 하지는 않습니다. 고객의 규모, 보안 요구사항, 기존 인프라에 따라 **필요한 만큼만 제공**할 수 있으면 납품 비용이 줄고, 도입 장벽이 낮아집니다.

### 컴포넌트별 분류

먼저, 우리 스택의 모든 컴포넌트를 **핵심(Core)**, **확장(Extended)**, **프리미엄(Premium)**으로 분류합니다:

```
┌─────────────────────────────────────────────────────────────────┐
│                    컴포넌트 분류 매트릭스                          │
│                                                                   │
│  ● Core (제품 동작에 필수)                                       │
│    RKE2, ArgoCD, nginx-ingress, Longhorn, cert-manager,          │
│    external-dns, Harbor                                           │
│                                                                   │
│  ◆ Extended (운영 품질 향상)                                     │
│    Keycloak(SSO), Vault(시크릿), ALBC(IP mode),                  │
│    Cilium ENI, Hubble, Grafana, Loki, Tempo, Mimir               │
│                                                                   │
│  ★ Premium (엔터프라이즈 전용)                                   │
│    Teleport(Zero-Trust Access), Backstage(IDP),                   │
│    Kyverno(Policy), OpenCost(FinOps),                             │
│    Multi-Tenancy 격리, AIOps Layer                                │
└─────────────────────────────────────────────────────────────────┘
```

### 제품 에디션 정의

| 에디션 | 대상 고객 | 포함 컴포넌트 | 인프라 규모 |
|--------|----------|-------------|-----------|
| **Community** | PoC / 스타트업 / 단일 팀 | ● Core만 | 3~5 노드 |
| **Standard** | 중소기업 / 단일 제품 운영 | ● Core + ◆ Extended | 5~10 노드 |
| **Enterprise** | 대기업 / 멀티테넌트 / 규제 산업 | ● Core + ◆ Extended + ★ Premium | 10+ 노드 |

### 에디션별 상세 기능 매핑

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Community        Standard         Enterprise          │
│                                                                         │
│  K8s (RKE2)          ✅              ✅               ✅                │
│  GitOps (ArgoCD)     ✅              ✅               ✅                │
│  Ingress (nginx)     ✅              ✅               ✅                │
│  Storage (Longhorn)  ✅              ✅               ✅                │
│  Registry (Harbor)   ✅              ✅               ✅                │
│  ─────────────────────────────────────────────────────────────────      │
│  SSO (Keycloak)      ❌              ✅               ✅                │
│  Secrets (Vault)     ❌              ✅               ✅                │
│  CNI (Cilium ENI)    ❌ (Canal)      ✅               ✅                │
│  LB (ALBC IP mode)   ❌ (CCM)       ✅               ✅                │
│  Observability(LGTM) ❌ (Grafana만) ✅               ✅                │
│  ─────────────────────────────────────────────────────────────────      │
│  Zero-Trust(Teleport)❌              ❌               ✅                │
│  IDP (Backstage)     ❌              ❌               ✅                │
│  Policy (Kyverno)    ❌              ❌               ✅                │
│  FinOps (OpenCost)   ❌              ❌               ✅                │
│  Multi-Tenancy 격리  ❌              ❌               ✅                │
│  AIOps               ❌              ❌               ✅ (v3.0+)        │
└─────────────────────────────────────────────────────────────────────────┘
```

### 에디션별 아키텍처 다이어그램

**Community Edition** — "바로 돌아가는 최소 구성"

```
┌────────────────────────────────────────────┐
│  RKE2 + Canal + CCM                         │
│  ArgoCD + nginx-ingress + Longhorn          │
│  cert-manager + external-dns + Harbor       │
│                                              │
│  인증: 기본 kubeconfig                       │
│  시크릿: K8s Secrets                         │
│  모니터링: Grafana (기본 대시보드)            │
└────────────────────────────────────────────┘
  → PoC, 데모, 소규모 팀 즉시 배포 가능
  → 운영 부담 최소, 학습 비용 낮음
```

**Standard Edition** — "프로덕션 운영을 위한 완성형"

```
┌────────────────────────────────────────────┐
│  RKE2 + Cilium ENI + ALBC (IP mode)        │
│  ArgoCD + nginx-ingress + Longhorn          │
│  cert-manager + external-dns + Harbor       │
│                                              │
│  인증: Keycloak SSO (전 서비스 통합)         │
│  시크릿: Vault (동적 시크릿, 자동 rotation)  │
│  모니터링: LGTM Stack (Metrics+Logs+Traces)  │
│  네트워크: Hubble (실시간 flow 관측)         │
└────────────────────────────────────────────┘
  → 단일 고객 프로덕션 환경에 적합
  → 3-Layer Identity Stack 중 L1(Keycloak) + L2(Vault) 제공
```

**Enterprise Edition** — "멀티테넌트 + 규제 대응 + 완전 자동화"

```
┌──────────────────────────────────────────────────────────┐
│  Standard Edition 전체 포함                                │
│  ──────────────────────────────────────────────────────── │
│  + Teleport (Zero-Trust SSH/K8s/DB 접근, 세션 녹화)       │
│  + Backstage (Developer Portal, 셀프서비스)               │
│  + Kyverno (Policy as Code, Admission Control)            │
│  + OpenCost (FinOps, 고객별 비용 분배)                    │
│  + Multi-Tenancy (Namespace 격리 + L7 NetworkPolicy)      │
│  + AIOps (v3.0 이후, 이상 탐지 + 자동 복구)              │
│                                                            │
│  3-Layer Identity Stack 완전체:                            │
│    L1: Keycloak (Human SSO)                                │
│    L2: Vault (Secrets + Workload Identity)                 │
│    L3: Teleport (Zero-Trust Access + 감사)                 │
└──────────────────────────────────────────────────────────┘
  → 대기업 멀티테넌트 납품에 적합
  → 금융/의료 등 규제 산업 컴플라이언스 대응
  → 완전한 감사 추적 + 정책 자동 집행
```

### 구축 가능성 분석 — 독립 배포가 가능한가?

각 에디션이 **독립적으로 배포 가능한지** 기술적 의존성을 분석합니다:

| 전환 경로 | 기술적 가능 여부 | 필요 작업 | 난이도 |
|-----------|----------------|----------|--------|
| Community 단독 배포 | ✅ 가능 | RKE2 기본 설치 + ArgoCD App-of-Apps | ⭐ 낮음 |
| Community → Standard 업그레이드 | ✅ 가능 | Canal→Cilium CNI 전환, Keycloak/Vault 추가 | ⭐⭐⭐ 높음 (CNI 전환은 재배포) |
| Standard 단독 배포 | ✅ 가능 | Terraform + ArgoCD로 처음부터 Standard 구성 | ⭐⭐ 중간 |
| Standard → Enterprise 업그레이드 | ✅ 가능 | Teleport/Backstage/Kyverno 추가 (무중단) | ⭐⭐ 중간 |
| Enterprise 단독 배포 | ✅ 가능 | Full Stack 한 번에 프로비저닝 | ⭐⭐ 중간 |

> **💡 핵심 주의사항**: Community → Standard 전환 시 **CNI 교체(Canal → Cilium)**는 클러스터 재배포가 필요합니다. 따라서 프로덕션 환경을 고려하는 고객에게는 처음부터 **Standard 이상**을 권장합니다. Standard → Enterprise는 컴포넌트 추가만으로 무중단 전환이 가능합니다.

### 번들링 전략 요약

```
고객 유형별 권장 에디션:

  "우리 제품을 빠르게 테스트하고 싶어요"
    → Community Edition (3노드, 30분 내 배포)

  "프로덕션에서 안정적으로 운영하고 싶어요"
    → Standard Edition (SSO + Vault + Cilium + Observability)

  "여러 고객사에 납품하고, 감사/컴플라이언스 대응이 필요해요"
    → Enterprise Edition (Full Stack + Multi-Tenancy + 감사 추적)

  "온프렘 폐쇄망에 설치해야 해요"
    → Standard 또는 Enterprise (RKE2 기반이므로 모든 에디션 폐쇄망 가능)
```

| 에디션 | 배포 시간 | 최소 노드 | 에어갭(폐쇄망) | 멀티테넌트 | 컴플라이언스 |
|--------|----------|----------|--------------|-----------|------------|
| Community | ~30분 | 3 | ✅ | ❌ | ❌ |
| Standard | ~2시간 | 5 | ✅ | ❌ | 부분 (SSO+Vault) |
| Enterprise | ~4시간 | 10+ | ✅ | ✅ | ✅ (감사+정책+격리) |

> **비즈니스 관점의 핵심**: 모든 에디션이 **동일한 RKE2 + ArgoCD 기반**이므로, IaC 코드의 80%를 공유하고 **에디션별 Helm values와 ArgoCD ApplicationSet**으로 차이를 관리할 수 있습니다. 이는 유지보수 비용을 최소화하면서 다양한 고객 세그먼트를 커버하는 전략입니다.

---

## 참고 문서

| # | 문서 | 내용 |
|---|------|------|
| 06 | [rke2-optimization-guide.md](06-rke2-optimization-guide.md) | CCM Static Manifests 통합, 닭과 달걀 문제 해결 |
| 07 | [cloud-provider-migration-report.md](07-cloud-provider-migration-report.md) | In-tree → Out-of-tree 마이그레이션 기술 분석 |
| 08 | [nlb-architecture.md](08-nlb-architecture.md) | NLB/CCM/ALBC 역할 구분, Instance vs IP Mode |
| 11 | [keycloak-idp-strategy.md](11-keycloak-idp-strategy.md) | Keycloak 도입 전략, OIDC SSO |
| 14 | [future-roadmap.md](14-future-roadmap.md) | EKS vs RKE2 판단, 전체 고도화 로드맵 |
| 16 | [architecture-evolution-decision.md](16-architecture-evolution-decision.md) | **최종 의사결정 문서** (버전별 진화, 스택 변경) |
| 17 | [cilium-cni-architecture.md](17-cilium-cni-architecture.md) | Cilium ENI Mode 전환 아키텍처 |
