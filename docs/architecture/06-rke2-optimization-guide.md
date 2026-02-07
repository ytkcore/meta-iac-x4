# Architecture: RKE2 Cluster Optimization Guide

본 문서는 RKE2 클러스터의 안정성과 확장성을 극대화하기 위해 수행된 최적화 전략, 특히 **인프라 레벨 컴포넌트(AWS CCM 등)의 클러스터 초기화 단계 통합**에 대해 기술합니다.

## 1. 아키텍처 최적화 전략: 인프라 레벨 컴포넌트 통합

RKE2 클러스터는 기본적으로 "Cloud Agnostic"을 지향하지만, 실제 운영 환경(AWS, GCP, Azure 등)에서는 각 클라우드 제공업체와의 긴밀한 통합이 필요합니다.

### 1.1 핵심 변경 사항: AWS CCM 통합
기존의 수동 또는 사후 설치 방식에서 벗어나, RKE2의 **Static Manifests** 기능을 활용하여 부트스트랩 단계에서 AWS Cloud Controller Manager(CCM)를 자동 배포하도록 최적화했습니다.

- **위치**: `/var/lib/rancher/rke2/server/manifests/aws-ccm.yaml`
- **배포 메커니즘**: **Static Manifests** 활용 (RKE2 엔진이 구동 시 로컬 파일 시스템의 YAML을 감지하여 자동 배포하는 내장 기능)
- **장점**: 외부 인터럽트 없이 부트스트랩 단계에서 인프라 초기화를 완결하여 "Zero-Touch" 프로비저닝 달성
- **최적화**: 노드가 `Ready` 상태가 전에도 설치가 진행되도록 `jobTolerations`를 추가하여 순환 의존성 해결

### 1.2 기술적 메커니즘 상세: Static Manifests

#### 1) Static Manifests란?
일반적인 쿠버네티스 자원 배포(Dynamic)는 API 서버 가동 후 운영자가 `kubectl` 명령어를 날리거나 ArgoCD와 같은 배포 도구가 API를 통해 주입하는 방식입니다. 반면, **Static Manifests**는 RKE2 서버 노드의 특정 경로(`/var/lib/rancher/rke2/server/manifests`)에 위치한 YAML 파일들을 엔진이 구동 시점에 로컬 파일 시스템에서 직접 감지하여 배포하는 내장 기능입니다.

#### 2) 하이브리드 구성 방식 (Dynamic + Static)
본 아키텍처는 유연한 환경 구성과 견고한 배포를 위해 두 방식을 결합했습니다.
- **Terraform (Dynamic)**: 클러스터 이름, VPC 환경 정보 등을 변수로 받아 실시간으로 인스턴스의 `User Data`를 생성합니다.
- **RKE2 (Static)**: 생성된 `User Data` 내의 스크립트가 실행되면서 `/manifests` 폴더에 최종 YAML 파일을 기록합니다. RKE2 엔진 입장에서는 이 파일을 "변하지 않는 정적 배포 파일"로 인식하여 우선적으로 처리합니다.

#### 3) '닭과 달걀' 문제 해결 원리
이 방식은 클러스터 초기화 단계의 교착 상태를 다음과 같이 해결합니다.
- **API 서버 의존성 배제**: 클러스터 API 서버가 완전히 건강하지 않거나 노드가 `uninitialized` 상태여도, RKE2 엔진은 파일 시스템을 통해 감지한 매니페스트를 최우선적으로 스케줄링하려고 시도합니다.
- **클러스터 자아(Cloud Identity) 확립**: 클러스터가 외부 도움 없이 스스로 AWS 환경을 인지하기 위한 최소 필수 데이터(CCM)를 가지고 태어나게 함으로써, 부트스트랩 병목을 원천적으로 차단합니다.

---

## 2. 왜 인프라 레벨 컴포넌트로 교체해야 하는가?

RKE2의 표준 기능(In-tree provider) 대신 외부(External) 인프라 레벨 컴포넌트를 사용하는 이유는 다음과 같습니다.

### 2.1 "cloud-provider=external" 설정의 필요성
쿠버네티스 성숙도 모델에 따라 기존의 In-tree Cloud Provider는 코어 코드에서 제거(Legacy 제거)되고 있으며, 최신 RKE2는 이를 외부(External)로 분리하는 공통 표준을 따릅니다.
- **독립적 생명주기**: 쿠버네티스 업그레이드 없이도 클라우드 특화 기능(CCM)만 별도로 업데이트 가능.
- **가벼운 코어**: 불필요한 클라우드 종속 코드를 제거하여 클러스터 안정성 향상.

### 2.2 "닭과 달걀" 문제(Chicken-and-Egg Problem) 해결
쿠버네티스 노드가 정상적으로 사용 가능(`Ready`)한 상태가 되려면 클라우드 제공업체의 리소스(인스턴스 타입, 네트워크 등) 정보가 확인되어야 합니다.
- **표준 RKE2(In-tree)**: 쿠버네티스 코어 코드에 종속되어 있어 업데이트가 느리고 유연성이 떨어집니다.
- **인프라 레벨(CCM)**: 노드가 `Ready`가 되기 위해 필수적인 정보를 제공합니다. 이를 ArgoCD와 같은 상위 레이어에서 배포하려고 하면, 배포 도구 자체가 실행될 노드가 없어서 배포가 중단되는 교착 상태가 발생합니다. **따라서 클러스터 가동의 전제 조건인 컴포넌트는 인프라 레이어에서 처리되어야 합니다.**

### 2.3 클라우드 네이티브 기능과의 최적 결합
외부 CCM을 사용하면 AWS의 최신 NLB(Network Load Balancer), 보안 그룹 관리, EC2 인스턴스 라이프사이클 이벤트를 쿠버네티스 표준 API와 즉각적으로 연동할 수 있습니다.

### 2.4 제어 평면과 데이터 평면의 분리
인프라 레벨 컴포넌트를 부트스트랩 단계에 포함시키면, 클러스터의 "최소 가동 요건"이 인스턴스 생성 시점에 완성됩니다. 이는 클러스터 재구성(Re-build)이나 재해 복구(DR) 시 복구 속도를 비약적으로 향상시킵니다.

---

## 3. 계층별 컴포넌트 배치 기준

어떤 컴포넌트를 어느 단계에서 관리할 것인지에 대한 당사의 아키텍처 표준입니다.

| 계층 | 관리 도구 | 대상 컴포넌트 | 결정 기준 |
|:---:|:---:|:---|:---|
| **L1: Infrastructure** | Terraform / RKE2 UserData | AWS CCM, CNI (Canal/Cilium), Storage CRDs | 노드 초기화(`Ready`)를 위한 필수 요소 |
| **L2: Bootstrap** | ArgoCD (App-of-Apps) | Ingress Controller, External-DNS, Cert-Manager | 기본 서비스 노출을 위한 공통 플랫폼 |
| **L3: Application** | ArgoCD | Business Applications, Databases | 실제 비즈니스 로직 및 사용자 서비스 |

---

## 4. 베스트 프랙티스 준수 항목 (Architecture Compliance)

현재 구축된 아키텍처는 글로벌 클라우드 네이티브 표준(Cloud Native Industry Standard)을 준수하며, 운영 효율성과 보안의 균형을 맞춘 최적화된 설계를 반영하고 있습니다.

### 4.1 GitOps & Declarative Infrastructure (ArgoCD + Terraform)
- **표준**: 인프라(L1)와 애플리케이션(L2/L3)의 계층을 분리하고, 모든 변경을 Git으로 추적하는 현대적 운영의 표준입니다.
- **강점**: **ArgoCD App-of-Apps 패턴**을 통해 부트스트랩을 완전히 자동화하여, 수동 개입 없는(Zero-Touch) 일관된 클러스터 배포 환경을 구현했습니다.

### 4.2 Split-Horizon DNS Architecture
- **표준**: 동일 도메인(`unifiedmeta.net`)에 대해 Public/Private Zone이 공존하는 환경에서, DNS 동기화 충돌을 방지하기 위한 검증된 패턴입니다.
- **강점**: **인스턴스 분리(Public/Private)** 전략을 통해 각 Zone의 레코드 무결성을 보장하고, 단일 장애 지점(SPOF) 위험을 분산시켰습니다.

### 4.3 Cloud Agnostic & External Providers
- **표준**: 쿠버네티스 코어의 경량화 방향(In-tree Removal)에 맞춰 **External Cloud Controller Manager(CCM)**를 채택했습니다.
- **강점**: RKE2의 **Static Manifests** 기능을 활용하여, 부트스트랩 시점에 CCM을 자동 주입함으로써 클라우드 인프라와 쿠버네티스 간의 "닭과 달걀" 문제를 원천적으로 해결했습니다.

### 4.4 Least Privilege Principle
- **표준**: 모든 컴포넌트에 대해 최소 권한 원칙(Principle of Least Privilege)을 적용합니다.
- **강점**: ExternalDNS의 IAM 정책을 특정 **Hosted Zone ARN으로 제한(Scoped Policy)**하여, 만약의 보안 사고 발생 시에도 영향을 최소화(Blast Radius Containment)하도록 설계했습니다.

---

## 5. 결론 및 향후 방향
AWS CCM 통합을 통해 우리는 **"인스턴스 생성 즉시 서비스 투입 가능"**한 수준의 자동화를 달성했습니다. 향후 모든 클라우드 특화 드라이버(CSI 등) 및 보안 정책(OIDC 등) 또한 이 계층 구조에 따라 최적화될 예정입니다.
