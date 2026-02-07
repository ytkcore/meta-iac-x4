# Architecture Decision Record: Kubernetes Bootstrap Strategy

이 문서는 Kubernetes 부트스트랩 전략의 진화 과정, 직면했던 기술적 문제들, 그리고 최종적으로 선택된 **"Pure GitOps with Infrastructure Context"** 아키텍처의 결정 배경을 상세히 기술합니다.

## 1. Objective (목표)
새로운 클러스터(EKS/RKE2) 환경에서 "플랫폼 레이어" (ArgoCD, Ingress, Cert-Manager, Rancher 등)를 **완전 자동화**되고, **재현 가능**하며, **보안상 안전**하게 프로비저닝하는 표준 방법을 확립합니다.

## 2. Evolution of Architecture (아키텍처 진화 과정)

### Phase 1: Terraform "God Mode" (폐기됨)
초기에는 Terraform이 모든 Helm Chart(`helm_release`)를 직접 설치하고 관리하는 방식을 고려했습니다.
- **접근 방식**: `main.tf` 파일 안에 ArgoCD, Nginx, Cert-Manager 등에 대한 `helm_release` 리소스를 모두 정의.
- **문제점**:
    - **State Drift (상태 불일치)**: Terraform State가 병목이 됩니다. 누군가 수동으로 Helm을 수정하거나 ArgoCD가 설정을 변경하면 Terraform과 충돌이 발생합니다.
    - **Complexity (복잡성)**: 수천 줄에 달하는 Helm Value 파일들을 Terraform 변수로 관리해야 하는 부담이 큽니다.
    - **No GitOps**: Day 2 운영 시에도 변경사항 반영을 위해 `terraform apply`를 실행해야 하므로, GitOps의 취지(Git push만으로 배포)와 맞지 않습니다.

### Phase 2: Hybrid / "Direct Apply" (과도기)
Terraform이 ArgoCD만 설치하고, 나머지 앱들의 Manifest(`Application` CRD)를 **직접 클러스터에 주입**하는 방식을 시도했습니다.
- **접근 방식**: Terraform이 `Application` CRD를 템플릿 렌더링 후 `kubectl_manifest`로 적용. 이후 ArgoCD가 이를 감지하여 배포.
- **장점**: "Zero-Touch" 부트스트랩 가능. 초기 Git 리포지토리 설정 없이도 인프라 배포 가능.
- **단점**:
    - **Split Brain (두뇌 분열)**: 앱의 *관리*는 ArgoCD가 하지만, 앱의 *정의(Definition)*는 Terraform이 쥐고 있는 구조적 모순 발생.
    - **Migration Friction (전환 마찰)**: "부트스트랩 앱"을 나중에 "GitOps 관리 앱"으로 전환하려면 Terraform State에서 제거해야 하는 불편함.

### Phase 3: Pure GitOps (최종 결정)
Terraform의 역할을 "GitOps 엔진을 시동 거는 것"까지만 엄격히 제한하기로 결정했습니다.
- **접근 방식**:
    1. Terraform은 **ArgoCD**만 설치합니다.
    2. Terraform은 Git 리포지토리를 바라보는 **Root Application** 하나만 등록합니다.
    3. 이후 모든 앱(Ingress 등)의 설치는 **ArgoCD가 전적으로 담당**합니다.
- **결정 이유 (Rationale)**:
    - **Single Source of Truth**: 모든 애플리케이션의 유일한 진실 공급원은 Git이어야 한다는 원칙 준수.
    - **Clean Handover**: Terraform은 클러스터와 컨트롤 플레인(ArgoCD)만 만들고, 열쇠를 Git에게 넘겨주는 깔끔한 역할 분담.

---

## 3. Key Challenges & Solutions (핵심 난제와 해결책)

### Challenge A: The "Dynamic Infrastructure" Paradox (동적 인프라의 역설)
**문제**: Pure GitOps 모델에서 Git의 Manifest는 정적(Static)입니다. 반면, AWS 인프라는 동적(Dynamic)입니다.
- 예: Ingress용 AWS Load Balancer(NLB)의 DNS 주소나 Zone ID는 생성 전에는 알 수 없습니다.
- 예: Terraform이 생성한 ACM 인증서 ARN은 매번 바뀔 수 있습니다.
- **Git은 이 값들을 미리 알 수 없습니다.** 이 값들을 `values.yaml`에 하드코딩하려면 별도의 스크립트가 필요하며, 이는 안티 패턴입니다.

**해결책: Infrastructure Context Injection (인프라 컨텍스트 주입)**
우리는 **"Infrastructure Context"**라는 패턴을 표준화했습니다.
1. **Terraform**이 모든 동적 값(VPC ID, ACM ARN, 도메인, 리전 등)을 수집합니다.
2. **Terraform**이 `kube-system/infra-context`라는 **Kubernetes Secret**을 생성합니다.
3. GitOps 앱(Helm Chart)들은 실행 시점에 이 Secret을 참조(`lookup` 함수 등 사용)하여 필요한 값을 동적으로 가져갑니다.

> **결과**: Git은 깨끗한 상태(Static)를 유지하고, 클러스터가 자신의 정체성(Identity) 정보를 스스로 내장하게 됩니다.

### Challenge B: Private Environments (폐쇄망 / OCI)
**문제**: 인터넷이 차단된 폐쇄망(Private VPC) 환경에서는 Bitnami 같은 공용 Helm 리포지토리에 접근할 수 없습니다.
**해결책: Harbor OCI Integration**
- 사내 **Harbor** 레지스트리를 투명한 OCI 프록시/캐시로 활용합니다.
- **Terraform 로직**:
    - Harbor 사용 가능 여부(`var.use_harbor_oci`)를 감지합니다.
    - 가능할 경우: ArgoCD가 Harbor(`oci://harbor.internal/...`)를 바라보도록 설정합니다.
    - 불가능할 경우: 공용 인터넷 망(Upstream)을 사용하도록 자동 전환됩니다.
- 이를 통해 **동일한 코드**로 공용망(Dev)과 폐쇄망(Prod)을 모두 지원할 수 있습니다.

---

## 4. Final Architecture Diagram

```mermaid
graph TD
    subgraph Terraform ["Step 1: Terraform (Bootstrap)"]
        TF_ARGO[Install ArgoCD]
        TF_ROOT[Apply Root App]
        TF_CTX[Create infra-context Secret]
    end

    subgraph Cluster ["Kubernetes Cluster"]
        Secret[Secret: kube-system/infra-context]
        note[Contains: ACM ARN, VPC ID, Domain]
        
        ArgoCD[ArgoCD Controller]
    end

    subgraph Git ["Git Repository"]
        RootApp[Root App]
        ChildApps[Apps: Ingress, Cert-Manager...]
    end

    TF_CTX -->|Injects| Secret
    TF_ARGO -->|Deploys| ArgoCD
    TF_ROOT -->|Registers| RootApp
    
    ArgoCD -->|Syncs| RootApp
    ArgoCD -->|Discovers| ChildApps
    
    ChildApps -.->|Reads (Lookup)| Secret
```

## 5. Summary of Responsibilities (역할 분담 요약)

| 컴포넌트 | 역할 및 책임 | 진실 공급원 (Source of Truth) |
| :--- | :--- | :--- |
| **Terraform** | VPC, EKS/RKE2, IAM, **ArgoCD 설치**, **Infra Context Secret 생성** | `*.tf` 파일 |
| **ArgoCD** | Git 변경사항 감지, 애플리케이션 동기화 (Sync) | 클러스터 내 구동 |
| **Git** | 플랫폼 앱(Ingress 등) 및 비즈니스 앱의 **정의(Definition)** | `helm-charts/`, `apps/` |
| **Infra Context** | Terraform이 만든 ID들을 GitOps 앱에 전달하는 **가교(Bridge)** | `Secret: infra-context` |

이 아키텍처는 최대의 자동화, 엄격한 역할 분리, 그리고 Day 2 운영의 안정성을 보장합니다.
