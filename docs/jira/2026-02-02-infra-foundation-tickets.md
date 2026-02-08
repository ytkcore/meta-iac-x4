# 지라 티켓 초안 (Jira Ticket Drafts)

## 티켓 1: [INFRA-001] 전사적 골든 이미지 전략 수립 및 적용 (AL2023)

### 설명
**목표**: 격리된 네트워크 환경 지원 및 보안 강화를 위해 모든 EC2 워크로드의 OS 이미지를 표준화합니다.

**요구사항**:
- `ami/golden.pkr.hcl` 경로에 Packer 템플릿 생성.
- Docker, AWS CLI, SSM 에이전트 사전 설치.
- `make init` 단계에서 AMI 체크 및 빌드 로직 통합.
- `ec2-instance` 공통 모듈이 골든 이미지를 기본값으로 사용하도록 업데이트.

**완료 조건 (Acceptance Criteria)**:
- [ ] `make init` 실행 시 최신 골든 이미지를 정상적으로 감지하거나 빌드함.
- [ ] 인터넷 연결 없이 생성된 인스턴스가 Docker 서비스를 즉시 구동함.
- [ ] 모든 인스턴스가 SSM 세션 매니저를 통해 관리됨.

---

## 티켓 2: [INFRA-002] DB 서브넷 보안 강화: NAT 제거 및 PrivateLink 통합

### 설명
**목표**: DB 서브넷에서 NAT Gateway 의존성을 제거하고 VPC 엔드포인트를 활용하여 엄격한 네트워크 격리를 구현합니다.

**요구사항**:
- `stacks/dev/00-network`에서 DB 티어의 NAT 라우팅 비활성화.
- `00-network` 스택에 `ssm`, `ssmmessages`, `ec2messages` 인터페이스 엔드포인트 구축.
- DB 라우팅 테이블이 S3 게이트웨이 엔드포인트를 사용하도록 보장.
- **[연관] INFRA-005**: DB 인바운드 규칙을 `ops-client` 및 `k8s-client` SG와 결합하여 IP 기반 허용 최소화.

**완료 조건 (Acceptance Criteria)**:
- [ ] DB 서브넷 라우팅 테이블에 NAT Gateway(0.0.0.0/0) 경로가 없음.
- [ ] DB 서브넷의 인스턴스가 PrivateLink를 통해 AWS SSM 서비스와 통신함.
- [ ] 엔드포인트 보안 그룹이 VPC CIDR 내의 443 트래픽만 허용함.
---

## 티켓 3: [INFRA-003] RKE2 인프라 파괴 자동화(Graceful Cleanup) 및 AWS 리소스 정밀 타격 로직 구현

### 설명
**목표**: Kubernetes에 의해 동적으로 생성되어 테라폼 상태 파일(tfstate) 외부에서 의존성을 방해하는 리소스(LB, ENI 등)를 자동 정리하여, 인프라 삭제 시 SG(Security Group) 삭제 지연 문제를 원천 해결합니다.

**요구사항**:
- **Identify-Verify-Automate 방법론**을 통한 고아 리소스 식별.
- `pre-destroy-hook.sh` 내에 `kubernetes.io/cluster/` 태그 기반 AWS CLI 정리 로직 추가.
- SG를 점유 중인 ENI(Network Interface)를 강제 `detach` 및 `delete` 하는 정밀 타격 로직 구현.
- Control Plane이 이미 종료된 상황에서도 동작하는 **AWS API Fallback** 메커니즘 구축.
- **[연관] INFRA-005**: 하이브리드 디커플링 아키텍처를 통해 SG 간 순환 참조를 근본적으로 제거하여 스크립트의 부담 완화.

**완료 조건 (Acceptance Criteria)**:
- [ ] `make destroy` 실행 시 클러스터 태그가 달린 LB와 ENI가 선제적으로 삭제됨.
* [ ] SG 삭제 시 발생하던 `DependencyViolation` 에러가 더 이상 발생하지 않음.
* [ ] Control Plane 부재 시 터널링 에러 없이 잔여물 정리가 수행됨.

---

## 티켓 4: [INFRA-004] 전사적 운영 가시성 확보를 위한 중앙 집중형 통합 로깅 시스템 구축

### 설명
**목표**: Makefile 명령 및 각종 자동화 스크립트의 실행 이력을 영구 기록하고, 운영자가 관심 있게 볼만한 핵심 이정표(Checkpoint) 위주로 로그를 구성하여 트러블슈팅 효율을 극대화합니다.

**요구사항**:
- `scripts/common/logging.sh` 중앙 집중형 로깅 유틸리티 표준화.
- Makefile의 모든 핵심 타겟(`plan`, `apply`, `destroy`)에 자동 로깅 훅 연동.
- 작업 유형별 로그 디렉토리 분리(`logs/terraform/`, `logs/global/`) 및 타임스탬프 기반 파일 생성.
- 전체 소스 코드 리팩토링 없이 Makefile 수준에서 통합하는 고효율 아키텍처 적용.
- **[연관] INFRA-005**: 디커플링된 보안 규칙의 동적 변경 및 삭제 과정을 로그로 남겨 운영 감사(Audit) 대응.

**완료 조건 (Acceptance Criteria)**:
- [ ] 모든 인프라 변경 작업이 `logs/` 디렉토리에 파일로 영구 저장됨.
- [ ] 로그 내에 작업 일시, 대상 스택, 상태(OK/WARN/ERR)가 명확히 기록됨.
- [ ] 색상 기반 콘솔 출력과 플레인 텍스트 기반 파일 기록이 동시에 수행됨.

---

## 티켓 5: [INFRA-005] Security Hybrid Decoupling: 전사적 스택(00-70) 대상 느슨한 결합 아키텍처 완성

### 설명
**목표**: RKE2 클러스터와 인프라 핵심 서비스(Bastion, DB, Harbor, Monitoring) 간의 상호 의존성을 제거하여 인프라의 유연성을 극대화하고, 파괴 시 발생하는 순환 참조 문제를 전사적으로 해결합니다.

**요구사항**:
- **00-Network**: VPC 모든 티어의 CIDR 대역을 `subnet_cidrs_by_tier`로 노출하여 위치 기반(Location) 보안의 근거 마련.
- **10-Security**: 3대 핵심 논리적 신원(Identity) SG 구축 (`k8s-client`, `ops-client`, `monitoring-client`).
- **40-Bastion**: 자체 SG 외에 `ops-client` SG를 정적 부착하여 DB/RKE2에 대한 영구적 관리 권한 확보.
- **45-Harbor & 60-DB**: `k8s-client`(노드용) 및 `ops-client`(관리자용) 조합의 하이브리드 인바운드 규칙 적용.
- **50-RKE2**: 노드 생성 시 `k8s-client`와 `monitoring-client` SG를 자동 주입하여 서비스 접근 및 관측성 확보.
- **70-Observability**: `monitoring-client` 정체성을 가진 노드들이 타 스택의 자원을 Scraping 할 수 있는 환경 제공.

**완료 조건 (Acceptance Criteria)**:
- [ ] 특정 스택(예: RKE2)의 존재 여부와 상관없이 타 서비스들의 보안 규칙이 정상적으로 유지됨.
- [ ] 전체 인프라 삭제(`make destroy-all`) 시 보안 그룹 삭제 단계에서 지연 시간 없이 초단위로 삭제 완료.
- [ ] Bastion, Monitoring 등 공통 서비스가 개별 클러스터 IP에 종속되지 않고 영구적인 접근 경로를 유지함.
