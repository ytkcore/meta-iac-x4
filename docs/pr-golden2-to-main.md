# Pull Request: Observability 스택 구축 및 인프라 고도화

## PR 정보

| 항목 | 내용 |
|:---|:---|
| Source Branch | `golden2` |
| Target Branch | `main` |
| 작업자 | ytk |
| 변경 규모 | 20개 파일, +363줄, -21줄 |

---

## 목적 (Objectives)

이 PR은 다음 목표를 달성하기 위한 인프라 고도화 작업입니다:

1. **Observability 구축**: Longhorn(스토리지) + Prometheus/Grafana(모니터링) 자동 배포
2. **AWS CCM 통합**: RKE2 클러스터가 AWS 리소스(ELB, EBS 등)를 네이티브하게 인식
3. **Split-Horizon DNS**: Public/Private Zone 분리로 내부/외부 접근 경로 최적화
4. **DB 보안 강화**: 데이터베이스 인스턴스의 아웃바운드 트래픽 제한

---

## 변경 내역 (Changes)

### 1. AWS Cloud Controller Manager (CCM) 통합

**배경**

기존 RKE2 클러스터는 AWS 리소스를 인식하지 못해, LoadBalancer 타입 Service 생성 시 ELB가 프로비저닝되지 않고, 노드에 `node.cloudprovider.kubernetes.io/uninitialized` Taint가 영구적으로 남아있었습니다.

**변경사항**

| 파일 | 변경 | 상세 내용 |
|:---|:---|:---|
| `modules/rke2-cluster/variables.tf` | 신규 변수 추가 | `enable_aws_ccm` (CCM 활성화), `disable_ingress` (RKE2 기본 Ingress 비활성화) |
| `modules/rke2-cluster/main.tf` | 태그 전파 | EC2 인스턴스에 `kubernetes.io/cluster/<name>=owned` 태그 추가로 CCM이 노드 인식 |
| `modules/rke2-cluster/templates/rke2-server-userdata.sh.tftpl` | 부트스트랩 로직 | `provider-id` 자동 주입, CCM 매니페스트 배포, Taint 자동 제거 스크립트 |
| `modules/rke2-cluster/templates/rke2-agent-userdata.sh.tftpl` | 워커 노드 정비 | 에이전트 초기화 스크립트 정리 |
| `stacks/dev/50-rke2/main.tf` | 옵션 전달 | 모듈에 `enable_aws_ccm = true`, `disable_ingress = true` 파라미터 추가 |

**영향 범위**

- 신규/기존 노드 모두 AWS CCM에 의해 자동 관리됨
- Service Type: LoadBalancer 사용 시 NLB 자동 프로비저닝

**참고사항**

- 관련 문서: `docs/architecture/rke2-optimization-guide.md` (신규 작성)

---

### 2. Split-Horizon DNS (ExternalDNS 분리)

**배경**

동일 도메인(`unifiedmeta.net`)에 대해 Public Zone에는 NLB 주소가, Private Zone에는 내부 IP가 등록되어야 합니다. 단일 ExternalDNS 인스턴스로는 이 요구사항을 충족할 수 없었습니다.

**변경사항**

| 파일 | 변경 | 상세 내용 |
|:---|:---|:---|
| `gitops-apps/bootstrap/external-dns-private.yaml` | 신규 생성 | Private Zone 전용 ExternalDNS. 내부 통신용 A 레코드(Node IP) 등록 담당 |
| `gitops-apps/bootstrap/nginx-ingress.yaml` | Annotation 추가 | NLB 연동 명시, `service.beta.kubernetes.io/aws-load-balancer-type: nlb` |

**영향 범위**

- 외부 사용자: Public DNS → NLB → Ingress Controller → Pod
- 내부 워크로드: Private DNS → Node IP → Pod (직접 통신)

**참고사항**

- Public ExternalDNS는 기존 `external-dns.yaml` 사용 (변경 없음)

---

### 3. Observability 스택 구축

**배경**

클러스터 운영 가시성 확보를 위해 분산 스토리지(Longhorn)와 모니터링(Prometheus/Grafana)이 필요합니다.

**변경사항**

| 파일 | 변경 | 상세 내용 |
|:---|:---|:---|
| `gitops-apps/platform/longhorn.yaml` → `gitops-apps/bootstrap/longhorn.yaml` | 경로 이동 | ArgoCD Root-App에 의해 자동 배포되도록 bootstrap 폴더로 이동 |
| `gitops-apps/platform/monitoring.yaml` → `gitops-apps/bootstrap/monitoring.yaml` | 경로 이동 | Prometheus/Grafana 스택 자동 배포 활성화 |
| `stacks/dev/70-observability/.terraform.lock.hcl` | 신규 생성 | Provider 버전 고정 (재현 가능한 빌드) |
| `stacks/dev/70-observability/versions.tf` | 심볼릭 링크 | `modules/common_versions.tf` 공유로 일관성 확보 |

**영향 범위**

- Longhorn: 모든 워커 노드에 CSI 드라이버 설치, PVC 자동 프로비저닝
- Monitoring: `monitoring` 네임스페이스에 Prometheus, Grafana, Alertmanager 배포

**접속 URL**

| 서비스 | URL |
|:---|:---|
| Longhorn UI | https://longhorn.unifiedmeta.net |
| Grafana | https://grafana.unifiedmeta.net (admin/fastcampus) |
| Prometheus | https://prometheus.unifiedmeta.net |

---

### 4. Database 보안 강화

**배경**

DB 인스턴스가 `0.0.0.0/0`으로 아웃바운드 트래픽을 허용하고 있어, 데이터 유출 또는 외부 C&C 서버 통신 위험이 존재했습니다.

**변경사항**

| 파일 | 변경 | 상세 내용 |
|:---|:---|:---|
| `modules/postgres-standalone/main.tf` | Egress 규칙 변경 | `0.0.0.0/0` → `vpc_cidr` (VPC 내부만 허용) |
| `modules/postgres-standalone/variables.tf` | 변수 추가 | `vpc_cidr` 입력 변수 정의 |
| `modules/postgres-standalone/user_data.sh.tftpl` | 템플릿 수정 | 변수 참조 오류 수정 |
| `modules/neo4j-standalone/main.tf` | Egress 규칙 변경 | Postgres와 동일 |
| `modules/neo4j-standalone/variables.tf` | 변수 추가 | `vpc_cidr` 입력 변수 정의 |
| `stacks/dev/60-db/main.tf` | 값 전달 | 모듈에 `vpc_cidr` 값 주입 |

**영향 범위**

- DB 인스턴스는 VPC 내부(RKE2 노드, Bastion 등)로만 통신 가능
- 외부 인터넷 접근 완전 차단

---

### 5. 운영 스크립트 및 문서화

**변경사항**

| 파일 | 변경 | 상세 내용 |
|:---|:---|:---|
| `scripts/common/check-status.sh` | 로직 추가 | 다중 Ingress Controller 감지, 오타 방지 검증 로직 |
| `stacks/dev/55-bootstrap/manual-bootstrap.yaml` | 경로 수정 | ArgoCD 부트스트랩 참조 경로 최신화 |
| `docs/architecture/rke2-optimization-guide.md` | 신규 작성 | CCM 통합 과정 및 트러블슈팅 가이드 문서화 |

---

## 검증 결과 (Verification)

| 항목 | 상태 | 비고 |
|:---|:---|:---|
| 노드 상태 | ✅ 모든 노드 Ready | 마스터 3, 워커 4 |
| CCM Taint 제거 | ✅ 자동 제거 확인 | `uninitialized` Taint 없음 |
| Public DNS | ✅ NLB Alias 등록 | argocd.unifiedmeta.net |
| Private DNS | ✅ Node IP 등록 | VPC 내부 해석 정상 |
| Longhorn | ✅ CSI 드라이버 정상 | PVC 프로비저닝 확인 |
| Grafana | ✅ 로그인 성공 | admin/fastcampus |
| DB Egress | ✅ VPC CIDR만 허용 | 외부 차단 확인 |

---

## 주의사항 (Notes)

1. **Terraform State**: `70-observability` 스택은 신규 생성되었으므로 `make apply` 시 리소스가 생성됩니다.
2. **ArgoCD Sync**: Git Push 후 ArgoCD가 자동 동기화합니다. 수동 Sync가 필요할 경우 UI에서 Refresh 버튼을 클릭하세요.
3. **Grafana 비밀번호**: 초기 비밀번호는 `fastcampus`이며, 프로덕션 배포 전 변경이 권장됩니다.

---

## 관련 문서

- [RKE2 Optimization Guide](docs/architecture/rke2-optimization-guide.md)
- [Bootstrap Strategy](docs/architecture/bootstrap-strategy.md)
