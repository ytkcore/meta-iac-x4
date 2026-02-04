# Teleport EC2 배포 가이드

> 개발/스테이징 환경용 EC2 기반 Teleport All-in-One 배포 가이드

---

## 목차
1. [아키텍처 개요](#1-아키텍처-개요)
2. [기술 스택](#2-기술-스택)
3. [사전 요구사항](#3-사전-요구사항)
4. [배포 절차](#4-배포-절차)
5. [초기 설정](#5-초기-설정)
6. [운영 가이드](#6-운영-가이드)
7. [트러블슈팅](#7-트러블슈팅)

---

## 1. 아키텍처 개요

### 1.1 "State-less Compute & State-full Backend"

EC2 인스턴스는 **상태를 가지지 않으며**, 모든 영구 데이터는 AWS 관리형 서비스(DynamoDB, S3)에 저장됩니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    15-teleport Stack                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  [인터넷] ───HTTPS(443)───▶ ┌────────────────┐                  │
│                              │  Public ALB    │◀── AWS WAF      │
│                              │  (TLS Termination)│  (20-waf)     │
│                              └───────┬────────┘                  │
│                                      │                           │
│                              HTTP:3080                           │
│                                      ▼                           │
│                      ┌───────────────────────────┐              │
│                      │  Teleport EC2 (t3.small)  │              │
│                      │  All-in-One               │              │
│                      │  ├─ Auth Service (3025)   │              │
│                      │  ├─ SSH Service           │              │
│                      │  └─ Proxy Service (3080)  │              │
│                      └───────────────────────────┘              │
│                         HA: enable_ha=true → 2대                 │
│                         (ap-northeast-2a, 2c)                    │
├─────────────────────────────────────────────────────────────────┤
│                    Data Plane (Backend)                          │
│  ┌─────────────────┐         ┌─────────────────────┐            │
│  │    DynamoDB     │         │         S3          │            │
│  │ (Cluster State) │         │ (Session Recording) │            │
│  │                 │         │ (Audit Logs)        │            │
│  └─────────────────┘         └─────────────────────┘            │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 설계 철학: EC2 vs Kubernetes

| 기준 | EC2 (현재) | Kubernetes |
|:---|:---|:---|
| **장애 격리** | ✅ K8s 장애 시에도 접근 가능 | ❌ K8s 장애 시 Teleport도 불가 |
| **구축 속도** | ✅ 10분 | ⚠️ 30분+ |
| **복잡도** | ✅ 낮음 | ⚠️ cert-manager, PV 의존 |
| **HA** | ✅ 2대 Static | ✅ 3대+ StatefulSet |
| **권장 환경** | Dev, Staging | Production |

> **"Chicken-and-Egg" 문제 해결**: K8s 클러스터 장애 시에도 Teleport를 통한 복구 접근 가능

---

## 2. 기술 스택

### 2.1 인프라 구성요소

| 구성요소 | 상세 |
|:---|:---|
| **Compute** | EC2 t3.small (1~2대) |
| **AMI** | Amazon Linux 2023 (Golden Image) |
| **네트워크** | Private Subnet (common tier) |
| **Load Balancer** | Application Load Balancer (Public) |
| **TLS** | AWS ACM (ALB에서 종료) |
| **DNS** | Route53 (`teleport.{base_domain}`) |

### 2.2 데이터 저장소

| 구성요소 | 용도 | 설정 |
|:---|:---|:---|
| **DynamoDB** | 클러스터 상태, 유저, 노드 정보 | PAY_PER_REQUEST |
| **DynamoDB** | 감사 이벤트 (audit) | 자동 생성 `*_audit` 테이블 |
| **S3** | 세션 녹화 파일 | 버전 관리, 암호화, Public Block |

### 2.3 보안 구성

| 구성요소 | 설정 |
|:---|:---|
| **IAM Role** | DynamoDB, S3, SSM 최소 권한 |
| **Security Group** | ALB→EC2:3080만 허용 |
| **2FA** | OTP (TOTP) 기본 활성화 |
| **WAF** | 20-waf 스택에서 ALB에 연결 |

### 2.4 Teleport 서비스 포트

| 포트 | 서비스 | 설명 |
|:---|:---|:---|
| 3023 | SSH Proxy | SSH Proxy Listen |
| 3024 | Tunnel | Reverse Tunnel |
| 3025 | Auth | 인증 서비스 (gRPC) |
| 3080 | Web/Proxy | Web UI & HTTPS Proxy (ALB 연결) |

---

## 3. 사전 요구사항

### 3.1 인프라 의존성

```
00-network → 10-security → 15-teleport → 20-waf → ...
```

**필수 스택:**
- `00-network`: VPC, Subnet (common tier)
- `10-security`: (선택) Security 관련 기본 구성
- Route53 Hosted Zone (base_domain)

### 3.2 로컬 도구

```bash
# 필수
aws-vault       # AWS 자격 증명 관리
terraform >= 1.5
make

# Teleport CLI (배포 후 설치)
brew install teleport  # macOS
```

### 3.3 필수 변수 (env.tfvars)

```hcl
# 기본 설정
region       = "ap-northeast-2"
env          = "dev"
project      = "meta"
base_domain  = "your-domain.com"

# Teleport 전용
ami_id           = "ami-xxxxxxxxx"   # Golden Image
instance_type    = "t3.small"
teleport_version = "17"              # Major 버전
email            = "admin@example.com"
enable_ha        = false              # true: 2대 멀티AZ
```

---

## 4. 배포 절차

### 4.1 스택 초기화 및 배포

```bash
# 1. Terraform 초기화
make init ENV=dev STACK=15-teleport

# 2. 배포 계획 확인
make plan ENV=dev STACK=15-teleport

# 3. 배포 실행
make apply ENV=dev STACK=15-teleport
```

### 4.2 예상 생성 리소스

| 리소스 | 수량 | 설명 |
|:---|:---:|:---|
| EC2 Instance | 1~2 | Teleport 서버 |
| DynamoDB Table | 1 | Backend 상태 |
| S3 Bucket | 1 | 세션 녹화 |
| ALB | 1 | 퍼블릭 진입점 |
| ALB Target Group | 1 | EC2 연결 |
| Security Group | 2 | ALB, EC2 각각 |
| ACM Certificate | 1 | TLS 인증서 |
| Route53 Record | 2 | DNS, Cert Validation |
| IAM Role | 1 | EC2 Instance Profile |

### 4.3 배포 검증

```bash
# DNS 확인
dig teleport.dev.your-domain.com

# ALB 헬스체크 확인
aws elbv2 describe-target-health \
  --target-group-arn $(terraform -chdir=stacks/dev/15-teleport output -raw target_group_arn)

# 웹 접속 확인
curl -I https://teleport.dev.your-domain.com
```

---

## 5. 초기 설정

### 5.1 관리자 계정 생성

SSM을 통해 EC2에 접속하여 최초 관리자를 생성합니다:

```bash
# 1. Instance ID 확인
INSTANCE_ID=$(aws-vault exec devops -- \
  terraform -chdir=stacks/dev/15-teleport output -json instance_ids | jq -r '.[0]')

# 2. SSM 세션 시작
aws-vault exec devops -- aws ssm start-session --target $INSTANCE_ID

# 3. 인스턴스 내에서 관리자 생성
sudo tctl users add admin --roles=editor,access
```

출력된 초대 URL을 브라우저에서 열어 **비밀번호**와 **OTP(2FA)**를 설정합니다.

### 5.2 tsh CLI 설정 (로컬)

```bash
# 로그인
tsh login --proxy=teleport.dev.your-domain.com:443

# 서버 목록 확인
tsh ls

# SSH 접속
tsh ssh user@node-name
```

---

## 6. 운영 가이드

### 6.1 HA 모드 전환

```hcl
# stacks/dev/15-teleport/terraform.tfvars
enable_ha = true  # 2대 멀티AZ 배포
```

```bash
make apply ENV=dev STACK=15-teleport
```

### 6.2 버전 업그레이드

```hcl
# 버전 변경
teleport_version = "18"  # 새 버전
```

```bash
# Rolling Update (HA 환경)
make apply ENV=dev STACK=15-teleport
```

### 6.3 월 예상 비용

| 항목 | 비용 (USD) |
|:---|---:|
| EC2 t3.small × 2 | ~$30 |
| ALB | ~$20 |
| DynamoDB | ~$0 (Free Tier) |
| S3 | ~$1 |
| **합계** | **~$50/월** |

---

## 7. 트러블슈팅

### 7.1 로그 확인

```bash
# SSM 접속 후
sudo journalctl -u teleport -f          # 서비스 로그
cat /var/log/user-data.log              # 설치 로그
cat /etc/teleport.yaml                  # 설정 파일
```

### 7.2 일반적인 문제

| 증상 | 원인 | 해결 |
|:---|:---|:---|
| ALB 헬스체크 실패 | Teleport 미시작 | `systemctl status teleport` 확인 |
| DynamoDB 권한 오류 | IAM Role 부족 | IAM Policy 확인 |
| 웹 접속 불가 | ACM 인증서 미검증 | Route53 레코드 확인 |
| SSM 연결 불가 | VPC Endpoint 없음 | NAT/VPC Endpoint 확인 |

### 7.3 서비스 재시작

```bash
sudo systemctl restart teleport
```

---

## 관련 문서

| 문서 | 설명 |
|:---|:---|
| [ADR-001-access-control-solution.md](ADR-001-access-control-solution.md) | 솔루션 선정 결정 문서 |
| [teleport-production-guide.md](teleport-production-guide.md) | K8s Helm 기반 HA 가이드 |
| [03-customer-delivery.md](research/03-customer-delivery.md) | 고객 납품 권장안 |

---

## 변경 이력

| 버전 | 날짜 | 변경 내용 | 작성자 |
|:---|:---|:---|:---|
| 1.0 | 2026-02-04 | 초안 작성 | Platform Team |
