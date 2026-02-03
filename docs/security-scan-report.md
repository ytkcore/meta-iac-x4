# 보안 취약점 스캔 보고서

**스캔 일시**: 2026-02-03 22:38 KST  
**스캔 대상**: `/Users/ytkcloud/cloud/meta` (Terraform, YAML, Shell Scripts)  
**스캔 범위**: 하드코딩된 비밀, 과도한 권한, 네트워크 노출, TLS 설정

---

## 요약 (Executive Summary)

| 위험도 | 발견 수 | 설명 |
|:---:|:---:|:---|
| 🔴 **Critical** | 3 | 하드코딩된 비밀번호가 Git에 노출됨 |
| 🟠 **High** | 5 | 과도한 네트워크 접근 허용 (0.0.0.0/0) |
| 🟡 **Medium** | 4 | TLS 검증 비활성화 / Insecure 모드 |
| 🟢 **Low** | 2 | 개선 권장 사항 |

---

## 🔴 Critical: 하드코딩된 비밀번호

### 1. Rancher Bootstrap Password

| 파일 | 라인 | 내용 |
|:---|:---:|:---|
| `gitops-apps/bootstrap/rancher.yaml` | 55 | `bootstrapPassword: "admin"` |
| `apps/rancher.yaml` | 33 | `bootstrapPassword: "admin"` |
| `gitops-apps/apps/rancher.yaml` | 33 | `bootstrapPassword: "admin"` |

**위험**: 기본 비밀번호가 Git 저장소에 평문으로 노출되어 있습니다. 누구나 이 비밀번호로 Rancher에 초기 접속할 수 있습니다.

**권장 조치**:
```yaml
# Before
bootstrapPassword: "admin"

# After (Kubernetes Secret 사용)
bootstrapPassword: ""  # 랜덤 생성
# 또는 existingSecret 참조
```

---

### 2. Harbor 기본 비밀번호 (템플릿 내 하드코딩)

| 파일 | 라인 | 내용 |
|:---|:---:|:---|
| `modules/harbor-ec2/templates/harbor.yml.tftpl` | 23 | `harbor_admin_password: Harbor12345` |
| `modules/harbor-ec2/templates/harbor.yml.tftpl` | 27 | `password: root123` (DB 비밀번호) |

**위험**: 이 값들은 템플릿 기본값이지만, 실제 배포 시 덮어쓰지 않으면 취약한 기본값이 사용됩니다.

**권장 조치**:
- 기본값 제거 또는 빈 문자열로 변경
- `var.admin_password`와 `var.db_password`에 대해 `sensitive = true` 설정 확인
- Terraform 실행 시 환경변수 또는 Vault에서 주입

---

### 3. Grafana Admin 비밀번호

| 파일 | 위치 | 상태 |
|:---|:---:|:---|
| `gitops-apps/bootstrap/monitoring.yaml` | 106-109 | ✅ `existingSecret` 사용 (양호) |
| (실제 Secret 생성 시) | N/A | `monitoring-grafana-secret`에 `admin` / `fastcampus` 저장됨 |

**상태**: 코드상으로는 Secret 참조 방식으로 양호하나, 실제 Secret 내용(`fastcampus`)이 약한 비밀번호입니다.

**권장 조치**: 프로덕션 배포 전 강력한 비밀번호로 교체

---

## 🟠 High: 과도한 네트워크 노출 (0.0.0.0/0)

### 발견된 위치

| 파일 | 라인 | 컨텍스트 | 위험도 |
|:---|:---:|:---|:---:|
| `modules/security-groups/main.tf` | 15, 36, 63, 109, 167, 231 | Egress 규칙 전체 허용 | 🟡 Medium |
| `modules/rke2-cluster/main.tf` | 204 | 노드 Egress 전체 허용 | 🟡 Medium |
| `modules/rke2-cluster/main.tf` | 576 | NLB Ingress 전체 허용 | 🟠 High |
| `stacks/dev/30-bastion/main.tf` | 71 | Bastion Egress 전체 허용 | 🟡 Medium |
| `stacks/dev/40-harbor/main.tf` | 164 | ALB Ingress 전체 허용 | 🟠 High |
| `modules/harbor-ec2/main.tf` | 79, 218 | Harbor 직접 접근 전체 허용 | 🟠 High |

**분석**:
- **Egress 0.0.0.0/0**: 일반적으로 허용 가능하나, DB 인스턴스에서는 제한 필요 (이미 `60-db`에서 수정됨 ✅)
- **Ingress 0.0.0.0/0**: Public 서비스(NLB, ALB)에는 필요하지만, IP Allowlist 고려 가능

**권장 조치**:
1. 관리용 포트(SSH, K8s API)는 `admin_cidrs`로 제한 (이미 일부 적용됨)
2. Harbor ALB는 VPC 내부만 허용하거나, CloudFront + WAF 도입 고려
3. 프로덕션 환경에서는 IP Allowlist 또는 VPN 필수

---

## 🟡 Medium: TLS 검증 비활성화

### 발견된 위치

| 파일 | 설정 | 용도 |
|:---|:---|:---|
| `modules/rke2-cluster/main.tf` | `harbor_tls_insecure_skip_verify` | Harbor self-signed 인증서 허용 |
| `stacks/dev/60-db/main.tf` | `harbor_insecure = true` | DB 인스턴스에서 Harbor 접근 시 TLS 검증 건너뛰기 |
| `stacks/dev/55-bootstrap/main.tf` | `server_insecure` | ArgoCD 서버 insecure 모드 |

**위험**: 중간자 공격(MITM)에 취약해질 수 있습니다.

**현재 상태 분석**:
- 이 설정들은 **Self-Signed 인증서 환경**(Harbor 내부 TLS)에서 불가피하게 필요합니다.
- ArgoCD의 경우 Ingress Controller에서 TLS를 종료하므로 백엔드는 insecure 모드가 일반적입니다.

**권장 조치**:
- Harbor에 Let's Encrypt 또는 Private CA 인증서 적용 후 `insecure = false`로 변경
- 프로덕션에서는 절대 `insecure` 옵션 사용 금지

---

## 🟡 Medium: IAM 와일드카드 권한

### 발견된 위치

| 파일 | 라인 | 내용 |
|:---|:---:|:---|
| `stacks/bootstrap-backend/main.tf` | 48 | `Action = "s3:*"` |

**분석**: Terraform State 버킷 관리용으로 넓은 권한이 필요하긴 하지만, `s3:*`는 과도합니다.

**권장 조치**:
```hcl
# Before
Action = "s3:*"

# After (Least Privilege)
Action = [
  "s3:GetObject",
  "s3:PutObject",
  "s3:DeleteObject",
  "s3:ListBucket"
]
```

---

## 🟢 Low: 개선 권장 사항

### 1. SSH Key 경로 평문 노출

| 파일 | 내용 |
|:---|:---|
| `stacks/dev/55-bootstrap/main.tf:301` | `sshPrivateKey = file(pathexpand(var.gitops_ssh_key_path))` |

**상태**: SSH 키 자체가 Git에 커밋되지는 않지만, `env.tfvars`에 경로가 기록됩니다.

**권장**: `gitops_ssh_key_path`를 환경변수(`TF_VAR_gitops_ssh_key_path`)로 주입

---

### 2. Sensitive 변수 미설정

다음 변수들에 `sensitive = true`가 필요합니다:

| 파일 | 변수 |
|:---|:---|
| `modules/harbor-ec2/variables.tf` | `admin_password`, `db_password` |
| `modules/rke2-cluster/variables.tf` | `harbor_password` |
| `modules/neo4j-standalone/variables.tf` | `neo4j_password` |
| `modules/postgres-standalone/variables.tf` | `postgres_password` |

---

## 조치 우선순위

| 순위 | 항목 | 담당 | 예상 시간 |
|:---:|:---|:---:|:---:|
| 1 | Rancher bootstrapPassword 제거/랜덤화 | DevOps | 30분 |
| 2 | Harbor 템플릿 기본 비밀번호 제거 | DevOps | 15분 |
| 3 | IAM `s3:*` 최소 권한으로 변경 | DevOps | 15분 |
| 4 | Sensitive 변수 설정 추가 | DevOps | 30분 |
| 5 | Harbor TLS 인증서 적용 후 insecure 제거 | Infra | 2시간 |

---

## 결론

현재 코드베이스는 **개발 환경 수준**의 보안 설정을 갖추고 있으며, 프로덕션 배포 전 위에서 언급된 Critical/High 항목들을 반드시 조치해야 합니다. 특히 **하드코딩된 비밀번호**는 즉시 제거되어야 합니다.

---

*Generated by Security Scan Agent*
