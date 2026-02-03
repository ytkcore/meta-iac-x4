# meta-iac-x4 아키텍처 분석 리포트

> 분석일: 2026-02-03
> 대상: 전체 코드베이스 (modules, stacks, gitops-apps, scripts, docs)

---

## 1. 아키텍처 완성도 평가

### 1.1 종합 점수: **B+ (78/100)**

| 영역 | 점수 | 등급 | 비고 |
|------|------|------|------|
| **코드 구조 및 모듈화** | 90/100 | A | 스택 분리, 모듈 재사용성 우수 |
| **네트워킹** | 88/100 | A | Multi-AZ, 티어별 서브넷, Split-horizon DNS |
| **보안** | 65/100 | C+ | IAM 과다 권한, 하드코딩된 비밀번호 |
| **운영성 (Day-2)** | 60/100 | C | DB 백업 부재, Auto-scaling 없음 |
| **GitOps** | 72/100 | B- | 기본 구조 양호하나 환경 분리 미흡 |
| **문서화** | 82/100 | A- | 스펙/아키텍처 문서 충실, 일부 불일치 |
| **CI/CD 자동화** | 55/100 | D+ | Makefile 기반 수동 워크플로우만 존재 |
| **재해복구 (DR)** | 50/100 | D | etcd 백업 없음, DB 복구 계획 없음 |
| **상태 관리** | 70/100 | B- | S3 백엔드 양호하나 DynamoDB 락 미설정 |
| **스크립트 품질** | 68/100 | C+ | macOS 전용 명령어로 Linux 호환성 문제 |

---

### 1.2 현재 아키텍처 구성도

```
                    ┌─────────────────────────────────┐
                    │         Route53 (Public)         │
                    │    *.unifiedmeta.net             │
                    └──────────┬──────────────────────┘
                               │
                    ┌──────────▼──────────────────────┐
                    │     ALB / NLB (Public Subnet)    │
                    │  Harbor ALB  │  Ingress NLB      │
                    └──────────┬──────────────────────┘
                               │
    ┌──────────────────────────▼──────────────────────────┐
    │                     VPC (10.0.0.0/16)                │
    │                                                      │
    │  ┌─────────────┐  ┌──────────────┐  ┌────────────┐ │
    │  │ Common Tier  │  │  K8s CP Tier │  │ K8s DP Tier│ │
    │  │  - Bastion   │  │  - CP x3     │  │ - Worker x4│ │
    │  │  - Harbor    │  │  - Internal  │  │ - Workloads│ │
    │  │              │  │    NLB       │  │            │ │
    │  └──────────────┘  └──────────────┘  └────────────┘ │
    │                                                      │
    │  ┌─────────────────────────────────────────────────┐ │
    │  │                  DB Tier                         │ │
    │  │   PostgreSQL (AZ-a)    Neo4j (AZ-c)            │ │
    │  └─────────────────────────────────────────────────┘ │
    │                                                      │
    │  Route53 Private Zone  │  NAT GW  │  VPC Endpoints  │
    └─────────────────────────────────────────────────────┘
```

---

## 2. 잘 구현된 부분 (강점)

### 2.1 스택 기반 분리 설계
- `00-network` → `10-security` → `30-bastion` → `40-harbor` → `50-rke2` → `55-bootstrap` → `60-db` → `70-observability`
- 각 스택이 독립적으로 `plan/apply/destroy` 가능
- `terraform_remote_state`를 통한 느슨한 결합 (순환 의존성 없음)
- 번호 기반 실행 순서가 명확

### 2.2 모듈 재사용성
- `modules/vpc/`: 540줄 규모의 완성도 높은 네트워크 모듈
- `modules/rke2-cluster/`: `for_each` 기반 노드 관리로 안정적인 변경
- `modules/ec2-instance/`: 범용 EC2 모듈로 Bastion/DB 등 활용

### 2.3 보안 설계 원칙
- SSM Session Manager 기반 접근 (SSH 키 제거)
- Break-glass SSH는 임시 보안 그룹 부착 방식으로만 허용
- Golden Image (Packer)로 SSH 데몬 자체를 비활성화
- EBS/S3 암호화 기본 활성화
- 논리적 보안 그룹 (`k8s_client`, `monitoring_client`)으로 최소 권한 원칙 적용

### 2.4 문서화
- `docs/Specification/`: 스택별 상세 사양서
- `docs/architecture/`: 설계 결정 문서 (네이밍, DNS, TLS, GitOps 등)
- `docs/runbooks/`: 운영 매뉴얼
- `docs/history/`: 프로젝트 진행 타임라인 (한국어)

### 2.5 네이밍 컨벤션
- `{env}-{project}-{workload}-{resource}-{suffix}` 형식 일관 적용
- 모든 리소스에 Environment/Project/ManagedBy 태그 부착

---

## 3. 보완이 필요한 영역 (심각도 순)

### 3.1 🔴 CRITICAL — 즉시 조치 필요

#### (1) DynamoDB State Locking 미설정
- **위치**: `stacks/dev/backend.hcl`
- **현상**: S3 백엔드만 설정, `dynamodb_table` 미지정
- **위험**: 동시 `terraform apply` 실행 시 상태 파일 손상 가능
- **조치**:
  ```hcl
  # backend.hcl에 추가
  dynamodb_table = "dev-meta-tfstate-lock"
  ```
  ```hcl
  # bootstrap-backend/main.tf에 DynamoDB 테이블 추가
  resource "aws_dynamodb_table" "terraform_lock" {
    name         = "${var.env}-${var.project}-tfstate-lock"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "LockID"
    attribute {
      name = "LockID"
      type = "S"
    }
  }
  ```

#### (2) 하드코딩된 기본 비밀번호
- **위치**:
  - `modules/harbor-ec2/variables.tf:95` → `admin_password = "Harbor12345"`
  - `modules/harbor-ec2/variables.tf:102` → `db_password = "root123"`
  - `gitops-apps/bootstrap/rancher.yaml:55` → `bootstrapPassword: "admin"`
- **위험**: 기본값 그대로 배포 시 보안 침해
- **조치**: default 값 제거, AWS Secrets Manager 또는 External Secrets Operator 통합

#### (3) 데이터베이스 백업 전략 부재
- **위치**: `modules/postgres-standalone/`, `modules/neo4j-standalone/`
- **현상**: 단독 EC2 인스턴스에 Docker 컨테이너로 실행, 백업 자동화 없음
- **위험**: 디스크 장애 시 데이터 완전 손실
- **조치**:
  - PostgreSQL: `pg_dump` 크론잡 + S3 업로드 스크립트
  - Neo4j: `neo4j-admin dump` + S3 업로드
  - 또는 AWS Backup 서비스 통합 (EBS 스냅샷)

#### (4) etcd 백업 미설정
- **위치**: `modules/rke2-cluster/`
- **현상**: RKE2 etcd 스냅샷 기능 미활성화
- **위험**: 클러스터 복구 불가능
- **조치**: RKE2 서버 설정에 etcd 자동 스냅샷 추가
  ```yaml
  # rke2 config
  etcd-snapshot-schedule-cron: "0 */6 * * *"
  etcd-snapshot-retention: 5
  etcd-s3: true
  etcd-s3-bucket: "dev-meta-etcd-backup"
  ```

### 3.2 🟠 HIGH — 다음 스프린트에서 조치

#### (5) RKE2 IAM 정책 과다 권한
- **위치**: `modules/rke2-cluster/main.tf:106-157`
- **현상**: `ec2:CreateSecurityGroup`, `ec2:DeleteSecurityGroup` 등 40+ 액션에 `Resource = "*"`
- **조치**: 클러스터 태그 기반으로 리소스 범위 제한
  ```json
  "Condition": {
    "StringEquals": {
      "aws:ResourceTag/kubernetes.io/cluster/CLUSTER_NAME": "owned"
    }
  }
  ```

#### (6) Auto-Scaling 미구현
- **위치**: `modules/rke2-cluster/main.tf`
- **현상**: 고정 노드 수 (CP 3, Worker 4), ASG 미사용
- **조치**:
  - Worker 노드를 ASG로 전환
  - Kubernetes Cluster Autoscaler 배포
  - 또는 Karpenter 도입 검토

#### (7) CI/CD 파이프라인 부재
- **현상**: Makefile 기반 수동 워크플로우만 존재
- **위험**: 코드 리뷰 없이 인프라 변경 가능, 감사 추적 어려움
- **조치**: GitHub Actions 기반 파이프라인 구축
  - PR → `terraform plan` 자동 실행 → 리뷰 → 머지 → `terraform apply`
  - OPA/Sentinel 정책 검증 추가

#### (8) GitOps 앱 디렉토리 구조 정리
- **현상**: `gitops-apps/bootstrap/`, `apps/`, `platform/`에 중복 정의 존재
  - rancher.yaml이 3곳에 존재
  - nginx-ingress가 2곳에 존재
- **조치**: 단일 소스 원칙 적용, README에 명시된 `platform/` 기준으로 통합

### 3.3 🟡 MEDIUM — 계획 수립 필요

#### (9) 스크립트 Linux 호환성 문제
- **위치**:
  - `scripts/rke2/get-kubeconfig.sh:120` → macOS `sed -i ''` 문법
  - `scripts/terraform/destroy-all.sh:56` → macOS `tail -r` 명령어
  - `scripts/common/init-env.sh:77-90` → `brew` 전용 패키지 설치
- **조치**: OS 감지 로직 추가 또는 POSIX 호환 명령어로 교체

#### (10) 환경별 분리 미흡 (GitOps)
- **현상**: 모든 GitOps 앱에 `unifiedmeta.net` 도메인이 하드코딩
- **조치**: ArgoCD ApplicationSet 또는 Helm values overlay로 환경별 분리

#### (11) EC2 Instance 모듈 출력값 부족
- **위치**: `modules/ec2-instance/outputs.tf`
- **현상**: `id`, `instance_id`, `private_ip`, `iam_role_name`만 출력
- **필요**: `public_ip`, `subnet_id`, `security_group_ids`, `ami_id` 추가

#### (12) Harbor TLS 기본값 비활성화
- **위치**: `modules/harbor-ec2/variables.tf:86-89`
- **현상**: `enable_tls` 기본값 `false`
- **조치**: 프로덕션 환경에서는 기본 `true`로 변경

### 3.4 🟢 LOW — 개선 권장 사항

| # | 항목 | 위치 | 설명 |
|---|------|------|------|
| 13 | VPC CIDR 유효성 검증 | `modules/vpc/variables.tf` | `validation` 블록 추가 |
| 14 | Network Policy 미정의 | `gitops-apps/` | Pod 간 트래픽 격리 필요 |
| 15 | Sealed Secrets 부재 | `gitops-apps/` | 시크릿 관리 체계 필요 |
| 16 | ArgoCD Project 분리 | `gitops-apps/` | `default` 프로젝트만 사용 중 |
| 17 | DB 헬스체크 모니터링 | `modules/postgres-standalone/` | CloudWatch 알람 부재 |
| 18 | Helm 버전 고정 | RKE2 user data template | `get_helm.sh` 버전 미지정 |
| 19 | Golden Image 문서 불일치 | `docs/architecture/golden-image-strategy.md` | docker-compose 포함 여부 불명확 |

---

## 4. 향후 협업 방식 제안

### 4.1 개발 워크플로우 표준화

```
                    ┌───────────────────────┐
                    │  Feature Branch 생성   │
                    │  (claude/feature-xxx)  │
                    └──────────┬────────────┘
                               │
                    ┌──────────▼────────────┐
                    │  코드 변경 + Plan 확인  │
                    │  make plan ENV=dev     │
                    │  STACK=xx-target       │
                    └──────────┬────────────┘
                               │
                    ┌──────────▼────────────┐
                    │   PR 생성 + 리뷰       │
                    │   (Plan 결과 첨부)      │
                    └──────────┬────────────┘
                               │
                    ┌──────────▼────────────┐
                    │  머지 → Auto Apply     │
                    │  (CI/CD 파이프라인)     │
                    └──────────┬────────────┘
                               │
                    ┌──────────▼────────────┐
                    │  Post-Apply 검증       │
                    │  (Health Check)         │
                    └───────────────────────┘
```

### 4.2 AI 협업 시 역할 분담

| 작업 유형 | 사람이 하는 부분 | AI가 하는 부분 |
|-----------|-----------------|---------------|
| **신규 스택 추가** | 요구사항 정의, 아키텍처 결정 | 모듈 코드 생성, 변수 설계, 테스트 |
| **보안 강화** | 정책 결정, 컴플라이언스 요건 | SG 규칙 분석, IAM 정책 최적화 |
| **트러블슈팅** | 증상 설명, 로그 제공 | 원인 분석, 해결책 제시, 코드 수정 |
| **문서화** | 방향성 제시, 리뷰 | 코드 기반 문서 자동 생성, 불일치 감지 |
| **코드 리뷰** | 최종 승인, 머지 결정 | Plan 분석, 변경 영향도 평가, 보안 검토 |
| **마이그레이션** | 일정/위험 관리 | import 블록 생성, state 이동 스크립트 |

### 4.3 효과적인 협업을 위한 컨텍스트 제공 가이드

AI에게 작업을 요청할 때 다음 정보를 함께 제공하면 효율적입니다:

```markdown
## 작업 요청 템플릿

### 무엇을 (What)
- 변경하려는 스택/모듈명
- 기대하는 결과

### 왜 (Why)
- 비즈니스 맥락 또는 기술적 이유

### 제약 조건 (Constraints)
- 변경 불가능한 리소스 (운영 중인 인스턴스 등)
- 다운타임 허용 여부
- 비용 제한

### 참고 정보 (Context)
- 관련 에러 로그
- 현재 terraform plan 결과
- 관련 문서나 스펙
```

### 4.4 권장 작업 우선순위 (로드맵)

```
Phase 1 — 안정화 (즉시)
├── DynamoDB State Locking 설정
├── 하드코딩된 비밀번호 제거
├── DB 백업 자동화 구축
└── etcd 스냅샷 활성화

Phase 2 — 보안 강화 (2주 내)
├── IAM 정책 최소 권한 적용
├── External Secrets Operator 도입
├── Network Policy 정의
└── Harbor TLS 기본 활성화

Phase 3 — 운영 고도화 (1개월 내)
├── CI/CD 파이프라인 (GitHub Actions)
├── Worker 노드 Auto-Scaling
├── DB 헬스체크 + CloudWatch 알람
└── 스크립트 Linux 호환성 수정

Phase 4 — 확장성 (분기 내)
├── 멀티 환경 지원 (stg, prod)
├── GitOps 환경 분리 (ApplicationSet)
├── ArgoCD Project/RBAC 분리
└── Disaster Recovery 테스트 자동화
```

### 4.5 코드 품질 유지를 위한 제안

1. **Pre-commit Hooks**: `tflint`, `terraform fmt`, `terraform validate` 자동 실행
2. **PR 체크리스트**:
   - [ ] `terraform plan`에 예상치 못한 destroy가 없는가?
   - [ ] 새 변수에 `description`과 `validation`이 있는가?
   - [ ] 민감한 값이 하드코딩되지 않았는가?
   - [ ] 관련 문서가 업데이트되었는가?
3. **스택 변경 시 영향도 매트릭스**:

```
변경 스택        │ 영향받는 하위 스택
────────────────┼───────────────────────────────
00-network      │ 10, 30, 40, 50, 55, 60, 70 (전체)
10-security     │ 30, 40, 50, 60
40-harbor       │ 50, 55, 60
50-rke2         │ 55, 60, 70
55-bootstrap    │ (GitOps 앱 전체)
60-db           │ (독립적)
70-observability│ (독립적)
```

---

## 5. 결론

meta-iac-x4는 **설계 철학과 구조적 완성도가 높은 프로젝트**입니다. 특히 스택 분리, 모듈 재사용, 보안 기본 원칙 (SSM, Golden Image), 문서화 측면에서 잘 설계되어 있습니다.

반면, **운영 안정성 (백업, DR, 상태 잠금)**과 **자동화 (CI/CD)**에서 개선이 필요합니다. 현재는 개발/PoC 단계에 적합한 수준이며, 프로덕션 전환을 위해서는 Phase 1~2의 항목을 우선 보완해야 합니다.

AI와의 협업에서는 **구조적 변경은 사람이 주도하고, 반복적인 코드 작성과 분석은 AI가 담당**하는 방식이 가장 효과적입니다. 작업 요청 시 충분한 컨텍스트(What/Why/Constraints)를 제공하면 더 정확하고 안전한 결과물을 얻을 수 있습니다.

---

*이 리포트는 2026-02-03 시점의 코드베이스를 기반으로 작성되었습니다.*
