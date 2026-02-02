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

**완료 조건 (Acceptance Criteria)**:
- [ ] DB 서브넷 라우팅 테이블에 NAT Gateway(0.0.0.0/0) 경로가 없음.
- [ ] DB 서브넷의 인스턴스가 PrivateLink를 통해 AWS SSM 서비스와 통신함.
- [ ] 엔드포인트 보안 그룹이 VPC CIDR 내의 443 트래픽만 허용함.
