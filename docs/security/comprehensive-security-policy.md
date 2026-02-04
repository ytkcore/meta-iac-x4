# 종합 보안 정책 (Comprehensive Security Policy)

> **Meta Infrastructure Platform 전체 보안 표준 및 운영 정책**

**최종 업데이트**: 2026-02-04  
**버전**: 1.0  
**담당**: Platform Team

---

## 목차

1. [개요](#1-개요)
2. [네트워크 보안](#2-네트워크-보안)
3. [접근 제어](#3-접근-제어)
4. [인증 및 권한 관리](#4-인증-및-권한-관리)
5. [데이터 보안](#5-데이터-보안)
6. [컨테이너 및 K8s 보안](#6-컨테이너-및-k8s-보안)
7. [시크릿 관리](#7-시크릿-관리)
8. [모니터링 및 감사](#8-모니터링-및-감사)
9. [취약점 관리](#9-취약점-관리)
10. [컴플라이언스](#10-컴플라이언스)
11. [인시던트 대응](#11-인시던트-대응)

---

## 1. 개요

### 1.1 보안 원칙

| 원칙 | 설명 |
|:---|:---|
| **Zero Trust** | 모든 접근은 인증/인가 필요, 네트워크 위치 신뢰 금지 |
| **Defense in Depth** | 다층 방어 (Network, Identity, Application, Data) |
| **Least Privilege** | 최소 권한 원칙, 필요한 권한만 부여 |
| **Secure by Default** | 기본 설정이 안전해야 함 |
| **Audit Everything** | 모든 접근 및 변경 사항 로깅 |

### 1.2 보안 계층 구조

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 7: Compliance & Audit (ISMS-P, ISO 27001)            │
├─────────────────────────────────────────────────────────────┤
│  Layer 6: Application Security (OWASP, SBOM)                │
├─────────────────────────────────────────────────────────────┤
│  Layer 5: Container Security (Image Scan, Runtime Policy)   │
├─────────────────────────────────────────────────────────────┤
│  Layer 4: Identity & Access (Teleport, IAM, RBAC)           │
├─────────────────────────────────────────────────────────────┤
│  Layer 3: Data Security (Encryption at Rest/Transit)        │
├─────────────────────────────────────────────────────────────┤
│  Layer 2: Network Security (SG, NACL, WAF)                  │
├─────────────────────────────────────────────────────────────┤
│  Layer 1: Infrastructure (Golden Image, Hardening)          │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 네트워크 보안

### 2.1 VPC 설계 원칙

| 항목 | 정책 | 구현 |
|:---|:---|:---|
| **Subnet 분리** | Public, Private, K8s, DB 계층 분리 | ✅ `modules/vpc` |
| **NAT Gateway** | Private 서브넷 아웃바운드 전용 | ✅ Multi-AZ HA |
| **VPC Endpoints** | AWS 서비스 Private 연결 | ✅ S3, ECR, SSM |
| **Route53 Private Zone** | 내부 DNS 전용 | ✅ `*.internal` |

### 2.2 Security Group 정책

#### 기본 원칙
- **Deny by Default**: 명시적 허용만 적용
- **Least Privilege**: 필요한 포트/프로토콜만 허용
- **Source Restriction**: `0.0.0.0/0` 최소화

#### 스택별 Security Group

| 스택 | Inbound 허용 | Outbound 제한 |
|:---|:---|:---|
| **05-security** | N/A (SG 정의만) | N/A |
| **15-teleport** | 443 (Public ALB) | HTTPS, DB |
| **30-bastion** | ❌ None (SSM Only) | HTTPS, SSH (VPC 내부) |
| **40-harbor** | 443 (ALB), 5000 (Private) | HTTPS, DB |
| **50-rke2** | 6443 (Internal NLB), 80/443 (Public NLB) | HTTPS, Harbor |
| **60-db** | 5432/7687 (VPC 내부만) | HTTPS (패치용) |

### 2.3 AWS WAF 정책

| 규칙 | 대상 | 목적 |
|:---|:---|:---|
| **Rate Limiting** | Teleport ALB | DDoS 방어 (100 req/5min) |
| **Geo Blocking** | Public ALB | 한국/미국 외 차단 (선택) |
| **SQL Injection** | 모든 ALB | OWASP Top 10 방어 |
| **XSS Protection** | 모든 ALB | Cross-Site Scripting 차단 |

**구현**: `20-waf` 스택, `modules/waf-acl`

### 2.4 네트워크 접근 제어

```hcl
# 관리용 CIDR (예시)
variable "admin_cidrs" {
  type    = list(string)
  default = ["1.2.3.4/32"]  # 회사 공인 IP
}

# 운영 환경: IP Allowlist 필수
# 개발 환경: 0.0.0.0/0 허용 가능 (WAF 적용)
```

---

## 3. 접근 제어

### 3.1 접근 방법 계층

| 우선순위 | 방법 | 대상 | 보안 수준 | 사용 시나리오 |
|:---:|:---|:---|:---:|:---|
| **1순위** | **Teleport** | SSH, K8s, DB, Web | ⭐⭐⭐⭐⭐ | 일상 운영, 감사 필요 |
| **2순위** | **AWS SSM** | EC2 | ⭐⭐⭐⭐ | Break-Glass, Teleport 장애 |
| **3순위** | **Direct SSH** | EC2 | ⭐⭐⭐ | 네트워크 디버깅 (긴급) |

### 3.2 Teleport 통합 접근제어

#### 아키텍처
```
[사용자] → [SSO + MFA] → [Teleport Proxy (ALB)]
                              ↓
              ┌───────────────┼───────────────┐
              ↓               ↓               ↓
         [SSH Agent]    [Kube Agent]    [DB Agent]
         (60-db EC2)    (50-rke2 Pod)   (Future)
```

#### Teleport 정책

| 항목 | 설정 | 비고 |
|:---|:---|:---|
| **SSO 통합** | Google Workspace | SAML 2.0 |
| **MFA** | 필수 (OTP) | 운영 환경 |
| **세션 녹화** | S3 저장 (1년) | ISMS-P 대응 |
| **Short-lived Cert** | 12시간 TTL | 비밀번호 불필요 |
| **RBAC** | Role-based | `admin`, `developer`, `viewer` |

**참고**: [ADR-001: 접근제어 솔루션 선정](../access-control/ADR-001-access-control-solution.md)

### 3.3 SSH 접근 정책

> **상세 내용**: [SSH 운영 정책](ssh-operational-policy.md) 참조

#### SSH 포트 전략

| 환경 | 포트 | 이유 |
|:---|:---:|:---|
| **운영 (Production)** | 22022 | Port Obfuscation |
| **개발 (Dev/Staging)** | 22 | 표준 호환성 |
| **엔터프라이즈 고객** | 22022 | 보안 감사 대응 |
| **SMB 고객** | 22 | 운영 단순화 |

#### Security Group 기본 정책
```hcl
# SSH 인바운드: 기본 차단
ingress {
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = []  # DENY ALL
}
```

### 3.4 Break-Glass 절차

| 단계 | 작업 | 승인 | 시간 제한 |
|:---:|:---|:---:|:---:|
| 1 | Jira 티켓 생성 + 사유 명시 | ✅ 필수 | - |
| 2 | 임시 SG 생성 (승인된 IP만) | ✅ 필수 | - |
| 3 | 인스턴스에 SG 부착 | ✅ 필수 | - |
| 4 | SSH 접속 및 작업 수행 | - | 1시간 |
| 5 | SG 제거 및 삭제 | ✅ 필수 | 즉시 |
| 6 | 작업 보고서 제출 | ✅ 필수 | 24시간 |

**참고**: [Break-Glass SSH 절차](../runbooks/break-glass-ssh.md)

---

## 4. 인증 및 권한 관리

### 4.1 IAM 정책

#### 최소 권한 원칙

```hcl
# ❌ Bad: 와일드카드 권한
Action = "s3:*"

# ✅ Good: 명시적 권한
Action = [
  "s3:GetObject",
  "s3:PutObject",
  "s3:DeleteObject",
  "s3:ListBucket"
]
```

#### IAM Role 전략

| 대상 | Role | 권한 범위 |
|:---|:---|:---|
| **RKE2 노드** | `rke2-node-role` | ECR Pull, S3 (Longhorn), CloudWatch |
| **DB 인스턴스** | `db-ec2-role` | SSM, CloudWatch, S3 (백업) |
| **Teleport 서버** | `teleport-role` | S3 (세션 녹화), Route53 |
| **Harbor 서버** | `harbor-role` | S3 (이미지 저장), Secrets Manager |

### 4.2 Kubernetes RBAC

#### Namespace 격리

| Namespace | 용도 | 접근 권한 |
|:---|:---|:---|
| `kube-system` | K8s 시스템 | Admin Only |
| `argocd` | GitOps | Platform Team |
| `longhorn-system` | 스토리지 | Platform Team |
| `monitoring` | Observability | Platform + SRE |
| `production` | 운영 워크로드 | Developer (제한적) |

#### Role 정의

```yaml
# 예시: Developer Role
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: production
  name: developer
rules:
- apiGroups: ["", "apps"]
  resources: ["pods", "deployments", "services"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get"]
```

### 4.3 Teleport RBAC

| Role | SSH | K8s | DB | Web Apps |
|:---|:---:|:---:|:---:|:---:|
| **admin** | ✅ All | ✅ All | ✅ All | ✅ All |
| **developer** | ⚠️ Read-only | ✅ Prod (제한) | ❌ None | ✅ ArgoCD |
| **viewer** | ❌ None | ⚠️ Read-only | ❌ None | ⚠️ Read-only |

---

## 5. 데이터 보안

### 5.1 암호화 정책

#### 전송 중 암호화 (Encryption in Transit)

| 프로토콜 | 요구사항 | 구현 |
|:---|:---|:---|
| **HTTPS** | TLS 1.2+ | ✅ ALB, NLB |
| **SSH** | Strong Ciphers | ✅ Golden Image |
| **K8s API** | TLS 1.3 | ✅ RKE2 기본값 |
| **DB 연결** | TLS 필수 | ✅ PostgreSQL, Neo4j |

#### 저장 데이터 암호화 (Encryption at Rest)

| 데이터 유형 | 암호화 방법 | 키 관리 |
|:---|:---|:---|
| **EBS 볼륨** | AWS KMS | AWS 관리형 키 |
| **S3 버킷** | SSE-S3 / SSE-KMS | AWS 관리형 키 |
| **RDS** | KMS 암호화 | AWS 관리형 키 |
| **Secrets** | Secrets Manager | AWS 관리형 키 |

### 5.2 백업 정책

| 대상 | 주기 | 보관 기간 | 암호화 |
|:---|:---:|:---:|:---:|
| **PostgreSQL** | 일 1회 | 30일 | ✅ KMS |
| **Neo4j** | 일 1회 | 30일 | ✅ KMS |
| **Longhorn PV** | 일 1회 | 7일 | ✅ S3 SSE |
| **Terraform State** | 자동 (S3 버전) | 90일 | ✅ KMS |

---

## 6. 컨테이너 및 K8s 보안

### 6.1 컨테이너 이미지 보안

#### Harbor 보안 정책

| 기능 | 설정 | 목적 |
|:---|:---|:---|
| **Image Scanning** | Trivy (자동) | 취약점 탐지 |
| **Content Trust** | Cosign 서명 | 이미지 무결성 |
| **SBOM** | Syft 생성 | 공급망 투명성 |
| **Retention Policy** | 최근 10개 유지 | 스토리지 최적화 |
| **Quota** | Project당 50GB | 리소스 제한 |

**참고**: [Harbor OCI 전략](../harbor-oci-strategic-analysis.md)

#### 이미지 정책

```yaml
# Kyverno Policy: 서명된 이미지만 허용
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signature
spec:
  validationFailureAction: enforce
  rules:
  - name: verify-signature
    match:
      resources:
        kinds:
        - Pod
    verifyImages:
    - imageReferences:
      - "harbor.dev.unifiedmeta.net/*"
      attestors:
      - entries:
        - keys:
            publicKeys: |-
              -----BEGIN PUBLIC KEY-----
              ...
              -----END PUBLIC KEY-----
```

### 6.2 Kubernetes 보안

#### Pod Security Standards

| Namespace | 정책 | 제한 사항 |
|:---|:---|:---|
| `kube-system` | Privileged | 시스템 컴포넌트 전용 |
| `longhorn-system` | Privileged | 스토리지 드라이버 |
| `monitoring` | Baseline | 일부 권한 필요 |
| `production` | **Restricted** | 최소 권한 |

#### Network Policy

```yaml
# 예시: DB 접근 제한
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-external-db
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: postgres
    ports:
    - protocol: TCP
      port: 5432
```

### 6.3 RKE2 보안 강화

| 설정 | 값 | 목적 |
|:---|:---|:---|
| `profile` | `cis-1.23` | CIS Benchmark 준수 |
| `secrets-encryption` | `true` | etcd 암호화 |
| `protect-kernel-defaults` | `true` | 커널 파라미터 보호 |
| `kube-apiserver-arg` | `--audit-log-maxage=30` | 감사 로그 보관 |

---

## 7. 시크릿 관리

### 7.1 시크릿 저장소

| 유형 | 저장소 | 용도 |
|:---|:---|:---|
| **인프라 시크릿** | AWS Secrets Manager | DB 비밀번호, API 키 |
| **K8s 시크릿** | Kubernetes Secret (etcd 암호화) | 앱 설정 |
| **GitOps 시크릿** | Sealed Secrets | Git 저장 가능 |
| **Terraform 변수** | 환경변수 (`TF_VAR_*`) | 로컬 개발 |

### 7.2 시크릿 정책

#### 금지 사항
- ❌ Git에 평문 시크릿 커밋
- ❌ 하드코딩된 비밀번호
- ❌ 기본 비밀번호 사용 (`admin`, `password`)
- ❌ 시크릿을 로그에 출력

#### 필수 사항
- ✅ Terraform 변수에 `sensitive = true` 설정
- ✅ 강력한 비밀번호 (16자 이상, 특수문자 포함)
- ✅ 주기적 비밀번호 변경 (90일)
- ✅ 시크릿 접근 로그 기록

### 7.3 Terraform Sensitive 변수

```hcl
# variables.tf
variable "db_password" {
  type      = string
  sensitive = true  # ✅ 필수
}

# 환경변수로 주입
export TF_VAR_db_password="$(aws secretsmanager get-secret-value \
  --secret-id db-password --query SecretString --output text)"
```

---

## 8. 모니터링 및 감사

### 8.1 로그 수집

#### CloudWatch Logs

| 로그 유형 | 경로 | Log Group | 보관 기간 |
|:---|:---|:---|:---:|
| **시스템 로그** | `/var/log/messages` | `/aws/ec2/{env}-{stack}/system` | 7일 |
| **인증 로그** | `/var/log/secure` | `/aws/ec2/{env}-{stack}/auth` | 30일 |
| **부팅 로그** | `/var/log/user-data.log` | `/aws/ec2/{env}-{stack}/bootstrap` | 7일 |
| **Docker 로그** | `/var/log/docker` | `/aws/ec2/{env}-{stack}/docker` | 7일 |

#### Teleport 감사 로그

| 이벤트 | 저장소 | 보관 기간 |
|:---|:---|:---:|
| **세션 녹화** | S3 | 1년 |
| **접근 로그** | DynamoDB | 1년 |
| **명령어 로그** | S3 | 1년 |

### 8.2 보안 이벤트 모니터링

#### CloudWatch Alarms

| 알람 | 조건 | 액션 |
|:---|:---|:---|
| **SSH 실패 5회 이상** | `/var/log/secure` 패턴 매칭 | SNS 알림 |
| **Root 로그인** | CloudTrail 이벤트 | SNS + Lambda (차단) |
| **SG 변경** | CloudTrail 이벤트 | SNS 알림 |
| **IAM 정책 변경** | CloudTrail 이벤트 | SNS 알림 |

### 8.3 감사 증적

| 항목 | 수집 방법 | 보관 기간 | 용도 |
|:---|:---|:---:|:---|
| **세션 녹화** | Teleport | 1년 | ISMS-P 감사 |
| **접근 로그** | CloudWatch + Teleport | 30일 | 이상 행위 탐지 |
| **명령어 로그** | Teleport Audit | 1년 | 사고 조사 |
| **Break-Glass 로그** | Jira + CloudWatch | 1년 | 컴플라이언스 |

---

## 9. 취약점 관리

### 9.1 취약점 스캔

#### 인프라 스캔

| 대상 | 도구 | 주기 |
|:---|:---|:---:|
| **Terraform 코드** | tfsec, Checkov | PR마다 |
| **Docker 이미지** | Trivy (Harbor) | Push 시 |
| **K8s 매니페스트** | Kubesec | PR마다 |
| **EC2 인스턴스** | AWS Inspector | 주 1회 |

#### 애플리케이션 스캔

| 대상 | 도구 | 주기 |
|:---|:---|:---:|
| **소스 코드** | SonarQube | PR마다 |
| **의존성** | Dependabot | 일 1회 |
| **SBOM** | Syft | 빌드 시 |

### 9.2 패치 관리

#### Golden Image 업데이트

| 항목 | 주기 | 트리거 |
|:---|:---:|:---|
| **보안 패치** | 월 1회 | CVE 발표 |
| **버전 업그레이드** | 분기 1회 | Docker, Teleport |
| **Base OS** | 반기 1회 | Amazon Linux 릴리스 |

#### 패치 절차

1. **스테이징 테스트**: 새 Golden Image 빌드 → Dev 환경 배포
2. **검증**: 기능 테스트 + 보안 스캔
3. **운영 배포**: Blue-Green 방식 (점진적 교체)
4. **롤백 준비**: 이전 AMI 3개 버전 유지

---

## 10. 컴플라이언스

### 10.1 ISMS-P 대응

| 요구사항 | 구현 | 증적 |
|:---|:---|:---|
| **접근 통제** | Teleport SSO + MFA | 세션 녹화 (S3) |
| **암호화** | TLS 1.2+, KMS | 설정 파일 |
| **로그 관리** | CloudWatch + Teleport | Log Group (30일) |
| **백업** | 일 1회 자동 | S3 버킷 |
| **취약점 관리** | Trivy, Inspector | 스캔 보고서 |
| **변경 관리** | GitOps (ArgoCD) | Git 커밋 로그 |

### 10.2 CIS Benchmark

| 항목 | 기준 | 구현 |
|:---|:---|:---|
| **SSH 설정** | CIS Amazon Linux 2023 | ✅ Golden Image |
| **K8s 설정** | CIS Kubernetes 1.23 | ✅ RKE2 `cis-1.23` 프로필 |
| **Docker 설정** | CIS Docker Benchmark | ✅ Golden Image |

### 10.3 감사 준비

#### 증적 문서

| 문서 | 경로 | 용도 |
|:---|:---|:---|
| **보안 정책** | 본 문서 | 전체 보안 표준 |
| **SSH 운영 정책** | `ssh-operational-policy.md` | SSH 접근 절차 |
| **ADR-001** | `access-control/ADR-001-*.md` | 접근제어 솔루션 선정 |
| **Break-Glass 절차** | `runbooks/break-glass-ssh.md` | 비상 접근 절차 |
| **보안 스캔 보고서** | `security-scan-report.md` | 취약점 현황 |

---

## 11. 인시던트 대응

### 11.1 보안 인시던트 분류

| 등급 | 정의 | 대응 시간 | 예시 |
|:---:|:---|:---:|:---|
| **P0 (Critical)** | 데이터 유출, 시스템 침해 | 즉시 | Root 계정 탈취 |
| **P1 (High)** | 서비스 중단, 권한 상승 | 1시간 | DDoS 공격 |
| **P2 (Medium)** | 취약점 발견, 정책 위반 | 24시간 | 패치되지 않은 CVE |
| **P3 (Low)** | 경미한 설정 오류 | 1주 | 불필요한 포트 오픈 |

### 11.2 대응 절차

#### 1단계: 탐지 및 보고
- CloudWatch Alarm → SNS → Slack
- 담당자 즉시 확인 (15분 이내)

#### 2단계: 격리
```bash
# 침해 의심 인스턴스 격리
aws ec2 modify-instance-attribute \
  --instance-id i-xxxxx \
  --groups sg-quarantine  # 모든 트래픽 차단
```

#### 3단계: 조사
- Teleport 세션 녹화 확인
- CloudTrail 이벤트 분석
- 로그 수집 및 보존

#### 4단계: 복구
- 침해 인스턴스 종료
- 새 Golden Image로 재배포
- 비밀번호/키 전체 교체

#### 5단계: 사후 분석
- 근본 원인 분석 (RCA)
- 재발 방지 대책 수립
- 정책 업데이트

### 11.3 연락처

| 역할 | 담당 | 연락처 |
|:---|:---|:---|
| **보안 책임자** | Platform Lead | Slack: #security-incident |
| **인프라 담당** | DevOps Team | Slack: #infra-oncall |
| **경영진 보고** | CTO | Email: cto@example.com |

---

## 부록

### A. 참고 문서

| 문서 | 경로 |
|:---|:---|
| Golden Image 명세서 | [golden-image-specification.md](../infrastructure/golden-image-specification.md) |
| SSH 운영 정책 | [ssh-operational-policy.md](ssh-operational-policy.md) |
| ADR-001 접근제어 | [ADR-001-access-control-solution.md](../access-control/ADR-001-access-control-solution.md) |
| Break-Glass 절차 | [break-glass-ssh.md](../runbooks/break-glass-ssh.md) |
| 보안 스캔 보고서 | [security-scan-report.md](../security-scan-report.md) |
| Harbor OCI 전략 | [harbor-oci-strategic-analysis.md](../harbor-oci-strategic-analysis.md) |

### B. 외부 참고 자료

- [AWS Security Best Practices](https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-standards-fsbp.html)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [Teleport Best Practices](https://goteleport.com/docs/production/)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)

### C. 변경 이력

| 버전 | 날짜 | 변경 내용 | 작성자 |
|:---|:---|:---|:---|
| 1.0 | 2026-02-04 | 초안 작성 | Platform Team |

---

**문서 승인**

| 역할 | 이름 | 서명 | 날짜 |
|:---|:---|:---|:---|
| 작성자 | Platform Team | - | 2026-02-04 |
| 검토자 | Security Team | - | - |
| 승인자 | CTO | - | - |
