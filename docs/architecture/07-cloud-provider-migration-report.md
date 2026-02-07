# Kubernetes Cloud Provider 아키텍처 변화 심층 분석 보고서

**작성일**: 2026-02-01  
**작성자**: DevOps Team  
**주제**: RKE2 AWS External Cloud Provider 마이그레이션 기술 분석 및 향후 방향성

---

## 1. 개요 (Executive Summary)

최근 수행한 RKE2 클러스터의 **External Cloud Controller Manager (CCM)** 통합 작업은 단순한 기능 수정이 아닌, Kubernetes 생태계의 거대한 아키텍처 변화(In-tree → Out-of-tree)를 반영하는 필수적인 업그레이드였습니다. 본 보고서는 이러한 변화가 왜 필요했는지, 기존 방식과 무엇이 달라졌는지, 그리고 이것이 글로벌 클라우드 네이티브 표준과 어떤 연관이 있는지를 심층 분석합니다.

---

## 2. 아키텍처 변화의 배경 (Why the Change?)

### 2.1. 과거: In-tree Provider (Monolithic)
Kubernetes 초기 설계에서는 AWS, GCP, Azure 등 주요 클라우드 공급자의 제어 코드(Node, Storage, LoadBalancer 관리 로직)가 Kubernetes **핵심 바이너리(`kube-controller-manager`) 안에 내장(In-tree)** 되어 있었습니다.

*   **문제점**:
    *   **비대해진 바이너리**: 모든 클라우드 벤더의 코드를 포함하므로 바이너리 크기가 계속 커짐.
    *   **릴리즈 종속성**: 특정 클라우드 벤더(예: AWS)의 버그를 수정하려면 Kubernetes 전체 버전을 릴리즈해야 함.
    *   **보안 리스크**: 사용하지 않는 벤더의 코드 취약점에도 노출될 가능성 존재.

### 2.2. 현재: Out-of-tree Provider (Modular)
Kubernetes v1.27부터 In-tree Provider 코드가 완전히 삭제(Removed)되었으며, **Cloud Controller Manager (CCM)** 라는 별도의 컴포넌트로 기능을 분리했습니다.

*   **장점 (Global Standard)**:
    *   **Decoupling**: Kubernetes 코어와 클라우드 로직의 완전한 분리.
    *   **독립적 라이프사이클**: 클라우드 벤더는 K8s 릴리즈 일정과 무관하게 버그 수정 및 기능을 배포 가능.
    *   **확장성**: 새로운 클라우드 공급자나 Private Cloud(OpenStack 등)가 K8s 코어 코드 수정 없이 플러그인 형태로 참여 가능.

---

## 3. 코드 레벨 변경 사항 심층 비교 (Code Comparison)

금번 작업에서 수정된 코드들은 이러한 아키텍처 변화를 수용하기 위한 조치들입니다.

| 구분 | Legacy (In-tree) | Current (Out-of-tree / CCM) | 기술적 함의 (Implication) |
| :--- | :--- | :--- | :--- |
| **RKE2 Userdata** | `cloud-provider-name: "aws"`<br>(또는 미지정) | `cloud-provider-name: "external"`<br>`node-name-from-...: true` | **책임 전가**: Kubelet은 더 이상 클라우드 API를 호출하지 않으며, 노드 객체 생성 시 "외부 관리자가 올 것이다"라고 마킹만 함. |
| **Node Status** | 부팅 즉시 `Ready` | 부팅 시 `NotReady`<br>Taint: `uninitialized` | **초기화 대기**: CCM이 실행되어 노드를 초기화(ProviderID 주입)하기 전까지 스케줄링이 차단됨 (Deadlock 주의). |
| **IAM Policy** | `elasticloadbalancing:*`<br>`ec2:Describe*` (일부) | **+ `autoscaling:Describe*`**<br>**+ `ec2:DescribeRouteTables`**<br>**+ `ec2:CreateTags`** 등 | **권한 세분화**: CCM은 단순 조회뿐만 아니라 라우팅 테이블 업데이트, 태깅 등 더 광범위한 인프라 제어 권한을 요구함. |
| **Component** | 없음 (Kubelet 내장) | **`aws-cloud-controller-manager`**<br>(Pod로 별도 배포) | **Day-2 Operation**: 클러스터 설치 후 *반드시* 추가로 설치해야 하는 필수 컴포넌트가 됨 (GitOps 관리 대상). |
| **Network** | 인스턴스 호스트명 사용 | **AWS Private DNS 매핑 필수** | **ID 정합성**: CCM은 AWS API가 반환하는 Private DNS Name을 기준으로 K8s 노드 객체를 매핑함. 불일치 시 관리 불가. |

---

## 4. 진행 간 마주한 기술적 난관 (Challenges)

이번 마이그레이션에서 겪은 주요 이슈들은 "변화된 책임 모델"을 명확히 이해하지 못했을 때 발생하는 전형적인 문제들이었습니다.

1.  **순환 의존성(Deadlock)의 모순**
    *   *상황*: CCM을 띄워야 노드가 초기화되는데, 노드가 초기화되지 않아 CCM 파드가 뜨지 않음.
    *   *해결*: "닭이 먼저냐 알이 먼저냐" 문제. 최초 부트스트랩 시에는 수동으로 Taint를 제거하거나, CCM 파드에 `Node: uninitialized` 상태를 용인하는 `Toleration`을 추가해야 함.

2.  **엄격해진 식별자 (Resource Tagging)**
    *   *상황*: 인프라 태그와 CCM 인자가 글자 하나만 달라도(`dev-meta` vs `meta-dev`) 동작 멈춤.
    *   *의미*: 과거엔 "대충" 동작하던 것들이, 이제는 **명시적 선언(Explicit Declaration)** 없이는 작동하지 않음. 이는 GitOps 철학("Code is Truth")과 일맥상통함.

---

## 5. 향후 방향성 및 글로벌 표준 (Future Direction)

### 5.1. CSI & CNI와의 통합 가속화
CCM(Compute) 분리는 시작일 뿐입니다. 스토리지(EBS, EFS)는 **CSI(Container Storage Interface)** 로, 네트워크는 **CNI** 로 이미 분리되었습니다. 앞으로의 인프라 관리는 이 3가지 축(Compute/Storage/Network)이 완전히 플러그인 형태로 동작하는 **Composable Infrastructure** 로 나아갑니다.

### 5.2. Cluster API (CAPI) 표준화
현재 우리는 Terraform으로 EC2를 만들고 RKE2를 올리지만, 글로벌 표준은 **Cluster API** 로 이동하고 있습니다.
*   **현재**: Terraform `aws_instance` + Userdata 스크립트.
*   **미래**: Kubernetes CRD(`Kind: AWSCluster`, `Kind: Machine`)로 인프라 선언. CCM 설정까지 자동화됨.

### 5.3. 결론 및 제언
금번 작업은 단순한 "버그 수정"이 아니라, **"레거시 아키텍처 청산 및 클라우드 네이티브 표준 준수"** 라는 큰 의미가 있습니다.

*   **제언 1**: 향후 모든 신규 클러스터는 설계 단계부터 `external` 모드를 기본값으로 채택해야 함.
*   **제언 2**: ArgoCD 부트스트랩 파이프라인에 CCM 배포를 최우선 순위(Wave -1)로 두어 Taint Deadlock을 자동 방지하는 고도화 필요.
