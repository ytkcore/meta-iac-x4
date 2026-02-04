# SSH 운영 정책 (SSH Operational Policy)

> **Meta Infrastructure Platform SSH 접근 제어 및 운영 표준**

**최종 업데이트**: 2026-02-04  
**버전**: 1.0  
**담당**: Platform Team

---

## 목차

1. [개요](#1-개요)
2. [SSH 접근 제어 전략](#2-ssh-접근-제어-전략)
3. [SSH 포트 정책](#3-ssh-포트-정책)
4. [Golden Image 통합](#4-golden-image-통합)
5. [스택별 SSH 정책](#5-스택별-ssh-정책)
6. [Break-Glass 절차](#6-break-glass-절차)
7. [보안 강화 설정](#7-보안-강화-설정)
8. [운영 시나리오](#8-운영-시나리오)
9. [감사 및 컴플라이언스](#9-감사-및-컴플라이언스)
10. [고객 납품 가이드](#10-고객-납품-가이드)

---

## 1. 개요

### 1.1 정책 목적

본 정책은 **Golden Image Port 22 기본값 + 배포 시 동적 변경** 패턴을 기반으로, 글로벌 엔터프라이즈 환경에서 검증된 SSH 접근 제어 전략을 정의합니다.

> **핵심 설계 철학**
> - Golden Image는 **표준 Port 22**로 빌드 (호환성, 재사용성)
> - 배포 시점에 `make init` 입력값으로 **동적 포트 변경** (22 또는 22022)
> - Security Group 기본 차단 + Teleport/SSM 우선 접근으로 **다층 방어**

### 1.2 적용 범위

| 대상 | 적용 여부 |
|:---|:---:|
| **EC2 인스턴스** (60-db, 30-bastion, 40-harbor, 15-teleport) | ✅ 적용 |
| **RKE2 노드** (50-rke2) | ⚠️ 제한적 (Break-Glass만) |
| **컨테이너** (K8s Pod) | ❌ 미적용 (kubectl exec 사용) |

### 1.3 현실적인 운영 과제 (Real-World Challenges)

#### 글로벌 기업들이 직면한 SSH 관리 문제

| 문제 | 현실 | 본 정책의 해결책 |
|:---|:---|:---|
| **Port 22 봇 스캔 폭주** | 하루 수천~수만 건 로그 노이즈 | Port 22022 옵션 + SG 차단 |
| **Teleport 장애 시 접근 불가** | 새벽 3시 장애 대응 불가능 | SSM Break-Glass 상시 준비 |
| **팀원 SSH 키 분실/유출** | 퇴사자 키 회수 어려움 | Teleport Short-lived Cert (12시간) |
| **감사 증적 부족** | "누가 언제 무엇을 했는지" 추적 불가 | Teleport 세션 녹화 (S3 1년 보관) |
| **고객사별 포트 요구사항 상이** | 금융권 22022, 스타트업 22 선호 | 배포 시 동적 변경 (`make init`) |
| **Golden Image 재빌드 부담** | 포트 변경마다 AMI 재생성 비용 | Port 22 기본값 + user-data 주입 |

#### Defense in Depth 계층

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 4: Audit (감사)                                       │
│           └─ Teleport 세션 녹화 + CloudWatch 로그            │
│                                                              │
│  Layer 3: Identity (인증)                                    │
│           └─ Teleport SSO + MFA + Short-lived Cert          │
│                                                              │
│  Layer 2: Network (네트워크) ⭐ 가장 중요                     │
│           └─ Security Group: SSH 인바운드 차단               │
│                                                              │
│  Layer 1: Port Obfuscation (포트 난독화) - 선택적            │
│           └─ SSH Port: 22 (기본) → 22022 (배포 시 변경)     │
│                                                              │
│  Layer 0: Break-Glass (비상 접근) ⭐ 필수                     │
│           └─ AWS SSM Session Manager (항상 활성)            │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. SSH 접근 제어 전략

### 2.1 접근 방법 우선순위

| 순위 | 방법 | 대상 | 보안 수준 | 사용 시나리오 | 감사 로그 |
|:---:|:---|:---|:---:|:---|:---:|
| **1순위** | **Teleport SSH** | EC2 (Agent 설치) | ⭐⭐⭐⭐⭐ | 일상 운영, 팀 협업 | ✅ 세션 녹화 |
| **2순위** | **AWS SSM** | 모든 EC2 | ⭐⭐⭐⭐ | Break-Glass, Teleport 장애 | ✅ CloudTrail |
| **3순위** | **Direct SSH** | EC2 (SG 오픈 시) | ⭐⭐⭐ | 네트워크 디버깅 (긴급) | ⚠️ CloudWatch |

### 2.2 Hybrid Access Pattern

```
┌─────────────────────────────────────────────────────────────┐
│                    일상 운영 (Normal Operations)             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  [개발자] → [Teleport Proxy (SSO+MFA)]                      │
│                      ↓                                       │
│              [Teleport SSH Agent]                            │
│                      ↓                                       │
│              [60-db EC2 Instance]                            │
│                                                              │
│  ✅ 세션 녹화 (S3)                                           │
│  ✅ 명령어 로그 (Audit Log)                                  │
│  ✅ RBAC (Role-based Access)                                │
│                                                              │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                 비상 상황 (Break-Glass)                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  [운영자] → [AWS Console / CLI]                             │
│                      ↓                                       │
│              [SSM Session Manager]                           │
│                      ↓                                       │
│              [EC2 Instance (SSM Agent)]                      │
│                                                              │
│  ✅ IAM 인증                                                 │
│  ✅ CloudTrail 로그                                          │
│  ⚠️ 세션 녹화 없음 (CloudWatch 로그만)                       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 2.3 접근 방법 선택 가이드

| 상황 | 권장 방법 | 이유 |
|:---|:---|:---|
| **DB 컨테이너 관리** | Teleport SSH | 세션 녹화, 팀 협업 |
| **로그 확인** | Teleport SSH | 명령어 감사 |
| **Teleport 서버 장애** | AWS SSM | Break-Glass |
| **네트워크 디버깅** (tcpdump 등) | Direct SSH (임시 SG) | 패킷 캡처 필요 |
| **긴급 복구** (새벽 장애) | AWS SSM | 빠른 접근 |

---

## 3. SSH 포트 정책

### 3.1 포트 전략: Golden Image Port 22 + 배포 시 동적 변경

#### 핵심 설계 원칙

> **Why Port 22 as Default in Golden Image?**
> 
> 1. **표준 호환성**: 모든 SSH 도구가 Port 22를 기본값으로 사용
> 2. **재사용성**: 하나의 Golden Image로 모든 환경 대응 (Dev/Prod/고객사)
> 3. **비용 효율**: 포트 변경마다 AMI 재빌드 불필요
> 4. **유연성**: 배포 시점에 `make init`으로 22 또는 22022 선택

#### 글로벌 기업 실무 사례

| 회사 유형 | Port 선택 | 이유 | 실제 사례 |
|:---|:---:|:---|:---|
| **FAANG** | **22** | SG 차단 + Teleport 의존, 포트 변경 불필요 | Google, Meta 내부 |
| **금융권** | **22022** | 감사 요구사항 "비표준 포트 사용" | JP Morgan, Goldman Sachs |
| **스타트업** | **22** | 운영 복잡도 최소화, SG 차단으로 충분 | Airbnb, Stripe 초기 |
| **공공기관** | **22022** | 정보보호 지침 "기본 포트 변경" | 한국 행정안전부 권고 |

#### Port Obfuscation 논쟁: 글로벌 보안 커뮤니티 의견

**찬성파 (Security by Obscurity 지지)**
- ✅ 실제 로그 분석: Port 22 → 22022 변경 시 **봇 스캔 90% 감소** (Shodan, Censys 데이터)
- ✅ `/var/log/auth.log` 노이즈 제거로 **진짜 공격 탐지 용이**
- ✅ "Defense in Depth" 철학: 작은 방어층이라도 추가하는 것이 유리
- ✅ 비용: $0 (설정 변경만)

**반대파 (False Sense of Security 경고)**
- ⚠️ 포트 스캔으로 **5분 내 발견 가능** (nmap -p 1-65535)
- ⚠️ 진짜 공격자는 **포트 변경으로 막을 수 없음**
- ⚠️ 운영 복잡도 증가 (문서화, 팀원 교육, 고객 지원)
- ⚠️ "Security by Obscurity"는 **근본 해결책 아님**

**실무 권장 (본 정책)**
```
✅ Security Group 차단 (필수) ← 진짜 방어
✅ Teleport/SSM 우선 접근 (필수) ← 진짜 방어
⚠️ Port 변경 (선택) ← 추가 방어층 (고객 요구사항에 따라)
```

#### 환경별 포트 선택 가이드

| 환경 | 권장 포트 | 이유 |
|:---|:---:|:---|
| **운영 (Production)** | **22 또는 22022** | 고객 요구사항에 따라 배포 시 선택 |
| **개발 (Dev/Staging)** | **22** | 표준 포트, 개발 편의성 |
| **엔터프라이즈 고객** | **22022** | 감사 요구사항 ("비표준 포트 사용") |
| **SMB 고객** | **22** | 운영 단순화, SG 차단으로 충분 |
| **공공기관** | **22022** | 정보보호 지침 준수 |

### 3.2 포트 변경 구현: Port 22 기본값 + 배포 시 동적 변경

#### Golden Image 기본 설정 (Port 22 고정)

```bash
# /etc/ssh/sshd_config (Golden Image 빌드 시)
Port 22  # ⭐ 항상 Port 22로 빌드 (표준 호환성)

# 이유:
# 1. 모든 환경에서 재사용 가능 (Dev/Prod/고객사)
# 2. AMI 재빌드 불필요 (비용 절감)
# 3. 배포 시점에 user-data로 동적 변경
```

#### 배포 시 동적 변경 (user-data)

```bash
#!/bin/bash
# user-data.sh
# 배포 시점에 Terraform 변수로 포트 주입

SSH_PORT=${ssh_port}  # make init 입력값 (22 또는 22022)

echo "[INFO] Configuring SSH port to $SSH_PORT"

# SSH 포트 변경
sed -i "s/^#Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
sed -i "s/^Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config

# SSH 재시작
systemctl restart sshd

# 확인 및 로깅
if ss -tlnp | grep -q ":$SSH_PORT"; then
  echo "[SUCCESS] SSH port changed to $SSH_PORT" >> /var/log/user-data.log
else
  echo "[ERROR] SSH port change failed" >> /var/log/user-data.log
  exit 1
fi
```

#### make init 워크플로우

```bash
# 1. make init 실행
$ cd stacks/dev/60-db
$ make init

# 2. SSH 포트 선택 프롬프트
Enter SSH port (22 or 22022) [default: 22]: 22022

# 3. env.tfvars 자동 생성
ssh_port = 22022

# 4. Terraform apply 시 user-data로 주입
$ make apply
# → EC2 부팅 시 Port 22 → 22022 자동 변경
```

#### Security Group 설정

```hcl
# Terraform 예시
resource "aws_security_group_rule" "ssh" {
  type              = "ingress"
  from_port         = var.ssh_port  # 22 또는 22022
  to_port           = var.ssh_port
  protocol          = "tcp"
  cidr_blocks       = []  # ❌ 기본 차단
  security_group_id = aws_security_group.main.id
}
```

### 3.3 실무 운영 시 주의사항

| 항목 | 주의사항 | 실제 사례 |
|:---|:---|:---|
| **Terraform 변수 일관성** | 모든 스택에서 `ssh_port` 변수 동일하게 사용 | 한 스택만 22022로 변경 시 혼란 |
| **Security Group 동기화** | 포트 변경 시 SG 규칙도 함께 업데이트 필수 | Port 22022로 변경했는데 SG는 22 허용 → 접속 불가 |
| **고객 문서화** | 납품 시 SSH 포트 명시 (README, 운영 가이드) | 고객사 "SSH 접속 안 됨" 문의 폭주 |
| **Break-Glass 안전성** | SSM은 SSH 포트와 무관하게 작동 (안심) | Port 22022로 변경해도 SSM 접근 가능 |
| **팀원 교육** | Port 22022 사용 시 `-p 22022` 옵션 교육 | 팀원들이 Port 22로 접속 시도 → 실패 |
| **모니터링 알람** | CloudWatch 알람에서 포트 번호 하드코딩 금지 | Port 변경 시 알람 작동 안 함 |

---

## 4. Golden Image 통합

### 4.1 SSH 설정 포함 항목

Golden Image(`meta-golden-image-al2023-*`)에는 다음 SSH 설정이 포함됩니다:

| 항목 | 기본값 | 변경 가능 | 변경 시점 |
|:---|:---|:---:|:---|
| **Port** | 22 | ✅ Yes | `make init` → user-data |
| **PasswordAuthentication** | no | ❌ No | - |
| **PubkeyAuthentication** | yes | ❌ No | - |
| **PermitRootLogin** | no | ❌ No | - |
| **MaxAuthTries** | 3 | ⚠️ Yes | 수동 수정 |
| **ClientAliveInterval** | 300 | ⚠️ Yes | 수동 수정 |

### 4.2 SSH 강화 설정 (기본 포함)

```bash
# /etc/ssh/sshd_config
Protocol 2
PermitEmptyPasswords no
X11Forwarding no
MaxAuthTries 3
IgnoreRhosts yes
HostbasedAuthentication no
PermitUserEnvironment no

# 강력한 암호화 알고리즘
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,diffie-hellman-group-exchange-sha256
```

### 4.3 user-data 변수 주입

| 변수 | 설정 항목 | 예시 |
|:---|:---|:---|
| `${ssh_port}` | SSH 포트 변경 | `22` → `22022` |
| `${hostname}` | 호스트네임 설정 | `db-postgres-01` |
| `${teleport_proxy}` | Teleport 서버 주소 | `teleport.dev.unifiedmeta.net` |
| `${teleport_token}` | Teleport Join Token | `xxxxx-xxxxx-xxxxx` |

**참고**: [Golden Image 명세서](../infrastructure/golden-image-specification.md)

---

## 5. 스택별 SSH 정책

### 5.1 스택별 SSH 활성화 매트릭스

| 스택 | SSH 활성화 | Teleport Agent | 접근 방법 | SSH 포트 | 비고 |
|:---|:---:|:---:|:---|:---:|:---|
| **60-db** | ✅ Yes | ✅ Yes | Teleport SSH (1순위) | var | Docker Compose 관리 |
| **50-rke2** | ⚠️ Optional | ❌ No (Pod) | SSM Only | var | K8s는 Teleport Kube Agent |
| **40-harbor** | ⚠️ Optional | ❌ No | SSM Only | var | 컨테이너 레지스트리 |
| **30-bastion** | ✅ Yes | ⚠️ Optional | Teleport SSH / SSM | var | Jump Host 역할 |
| **15-teleport** | ✅ Yes | ❌ N/A | SSM Only | var | Teleport 서버 자체 관리 |

### 5.2 Security Group 정책

#### 기본 정책: SSH 인바운드 차단

```hcl
# 모든 스택 공통
resource "aws_security_group_rule" "deny_ssh" {
  type              = "ingress"
  from_port         = var.ssh_port
  to_port           = var.ssh_port
  protocol          = "tcp"
  cidr_blocks       = []  # ❌ DENY ALL
  security_group_id = aws_security_group.main.id
}
```

#### Break-Glass용 임시 SG (사전 준비)

```hcl
# 평시에는 미사용, 비상 시 수동 부착
resource "aws_security_group" "emergency_ssh" {
  name        = "emergency-ssh-${var.env}"
  description = "Emergency SSH access (Break-Glass)"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress {
    from_port   = var.ssh_port
    to_port     = var.ssh_port
    protocol    = "tcp"
    cidr_blocks = var.admin_cidrs  # 승인된 IP만
  }

  tags = {
    Name        = "emergency-ssh-${var.env}"
    Environment = var.env
    Purpose     = "Break-Glass"
  }
}
```

---

## 6. Break-Glass 절차

### 6.1 사전 조건

- **평상시**: SSH 인바운드 규칙 없음 (Security Group 차단)
- **비상 시**: 임시 Security Group 수동 부착
- **승인**: Jira 티켓 또는 Slack 승인 필수

### 6.2 운영 규칙

| 항목 | 요구사항 |
|:---|:---|
| **사전 승인** | Jira 티켓 생성 + 사유 명시 |
| **시간 제한** | 최대 1시간, 작업 종료 후 즉시 원복 |
| **소스 IP 제한** | 승인된 공인 IP만 허용 (단일 IP 권장) |
| **작업 로그** | 실행 명령어, 변경 내역, 원인/조치 기록 |
| **사후 보고** | 작업 완료 후 24시간 내 보고서 제출 |

### 6.3 Break-Glass 절차

#### Step 1: 승인 획득

```markdown
# Jira 티켓 예시
제목: [Break-Glass] DB 서버 긴급 SSH 접근 요청
내용:
- 대상 인스턴스: i-xxxxx (60-db-postgres-01)
- 사유: PostgreSQL 컨테이너 재시작 실패, 로그 확인 필요
- 예상 작업 시간: 30분
- 승인자: @platform-lead
```

#### Step 2: 임시 Security Group 생성

```bash
# 1. 임시 SG 생성
SG_ID=$(aws ec2 create-security-group \
  --group-name "temp-ssh-emergency-$(date +%Y%m%d-%H%M)" \
  --description "Emergency SSH access - Ticket: INFRA-123" \
  --vpc-id vpc-xxxxx \
  --query 'GroupId' --output text)

# 2. 인바운드 규칙 추가 (승인된 IP만)
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 22 \
  --cidr <APPROVED_IP>/32
```

#### Step 3: 인스턴스에 SG 부착

```bash
# 기존 SG 확인
INSTANCE_ID="i-xxxxx"
ORIGINAL_SG=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].SecurityGroups[*].GroupId' \
  --output text)

# 임시 SG 추가 (기존 SG 유지)
aws ec2 modify-instance-attribute \
  --instance-id $INSTANCE_ID \
  --groups $ORIGINAL_SG $SG_ID
```

#### Step 4: SSH 접속 및 작업

```bash
# SSH 접속
ssh -p 22 -i ~/.ssh/meta-key.pem ec2-user@<instance-public-ip>

# 작업 수행 (예시)
docker ps
docker logs postgres-container
docker restart postgres-container

# 작업 로그 기록
history > /tmp/break-glass-$(date +%Y%m%d).log
```

#### Step 5: 원복 (필수)

```bash
# 1. SG 제거
aws ec2 modify-instance-attribute \
  --instance-id $INSTANCE_ID \
  --groups $ORIGINAL_SG

# 2. 임시 SG 삭제
aws ec2 delete-security-group --group-id $SG_ID

# 3. 확인
aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].SecurityGroups'
```

#### Step 6: 사후 보고

```markdown
# Jira 티켓 업데이트
작업 완료 보고:
- 작업 시간: 2026-02-04 14:30 ~ 14:50 (20분)
- 수행 작업: PostgreSQL 컨테이너 재시작
- 원인: 메모리 부족으로 인한 OOM Killer 발동
- 조치: max_connections 설정 조정 (100 → 50)
- 원복 확인: SG 제거 완료 (14:52)
- 재발 방지: CloudWatch 메모리 알람 추가
```

### 6.4 Break-Glass 자동화 스크립트 (선택)

```bash
#!/bin/bash
# break-glass-ssh.sh

set -e

INSTANCE_ID=$1
APPROVED_IP=$2
DURATION=${3:-3600}  # 기본 1시간

if [ -z "$INSTANCE_ID" ] || [ -z "$APPROVED_IP" ]; then
  echo "Usage: $0 <instance-id> <approved-ip> [duration-seconds]"
  exit 1
fi

# SG 생성 및 부착
echo "Creating emergency SG..."
# ... (위 스크립트 내용)

# 시간 제한 후 자동 원복
echo "SSH access granted for $DURATION seconds"
sleep $DURATION

echo "Auto-revoking SSH access..."
# ... (원복 스크립트)
```

---

## 7. 보안 강화 설정

### 7.1 SSH 데몬 설정

```bash
# /etc/ssh/sshd_config

# 기본 보안
Protocol 2
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
X11Forwarding no

# 인증 제한
MaxAuthTries 3
MaxSessions 10
LoginGraceTime 60

# 세션 유지
ClientAliveInterval 300
ClientAliveCountMax 2

# 접근 제어
AllowUsers ec2-user ssm-user
DenyUsers root

# 암호화 강화
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,diffie-hellman-group-exchange-sha256

# 로깅
SyslogFacility AUTHPRIV
LogLevel VERBOSE
```

### 7.2 커널 파라미터

```bash
# /etc/sysctl.d/99-security.conf

# IP 포워딩 비활성화
net.ipv4.ip_forward = 0

# ICMP 리디렉트 차단
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0

# SYN Flood 방어
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048

# ASLR 활성화
kernel.randomize_va_space = 2
```

### 7.3 사용자 계정 정책

| 계정 | 용도 | sudo 권한 | 기본 셸 | SSH 허용 |
|:---|:---|:---:|:---:|:---:|
| **ec2-user** | AL2023 기본 | ✅ Yes | bash | ✅ Yes |
| **ssm-user** | SSM Session Manager | ✅ Yes | bash | ⚠️ SSM Only |
| **root** | 시스템 관리 | - | bash | ❌ No |

---

## 8. 운영 시나리오

### 8.1 일상 운영: DB 서버 접속

```bash
# Teleport 로그인
tsh login --proxy=teleport.dev.unifiedmeta.net

# SSH 접속
tsh ssh ec2-user@db-postgres-01

# Docker 컨테이너 관리
docker ps
docker logs -f postgres-container
docker exec -it postgres-container psql -U postgres
```

### 8.2 비상 상황: Teleport 장애

```bash
# AWS SSM 사용
aws ssm start-session --target i-xxxxx

# 또는 AWS Console에서 "Connect" → "Session Manager"
```

### 8.3 네트워크 디버깅

```bash
# Break-Glass 절차 수행 후
ssh -p 22 ec2-user@<instance-ip>

# 패킷 캡처
sudo tcpdump -i eth0 -w /tmp/capture.pcap

# 네트워크 연결 확인
netstat -tulpn
ss -tulpn
```

### 8.4 RKE2 노드 디버깅

```bash
# Option A: kubectl debug (권장)
kubectl get nodes
kubectl debug node/ip-10-0-1-5 -it --image=ubuntu

# Option B: SSM
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*rke2*" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
aws ssm start-session --target $INSTANCE_ID
```

---

## 9. 감사 및 컴플라이언스

### 9.1 감사 증적 요구사항

| 항목 | 수집 방법 | 보관 기간 | 용도 |
|:---|:---|:---:|:---|
| **세션 녹화** | Teleport Session Recording | 1년 | ISMS-P 감사 |
| **접근 로그** | CloudWatch Logs (`/var/log/secure`) | 30일 | 이상 행위 탐지 |
| **명령어 로그** | Teleport Audit Log | 1년 | 사고 조사 |
| **Break-Glass 로그** | Jira Ticket + CloudWatch | 1년 | 컴플라이언스 |

### 9.2 CloudWatch Logs 설정

```json
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/secure",
            "log_group_name": "/aws/ec2/{env}-{stack}/auth",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 30,
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/aws/ec2/{env}-{stack}/system",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 7
          }
        ]
      }
    }
  }
}
```

### 9.3 Teleport 감사 로그 조회

```bash
# 세션 목록 조회
tctl get events --type=session.start --format=json

# 특정 사용자 세션 조회
tctl get events --type=session.start --format=json | \
  jq '.[] | select(.user == "user@example.com")'

# 세션 재생
tsh play <session-id>
```

### 9.4 ISMS-P 대응

| 요구사항 | 구현 | 증적 |
|:---|:---|:---|
| **비밀번호 대신 인증서** | ✅ Teleport Short-lived Cert | Teleport 설정 |
| **MFA 필수** | ✅ SSO (Google) + OTP | SSO 로그 |
| **세션 녹화** | ✅ Teleport S3 Recording | S3 버킷 |
| **접근 로그** | ✅ CloudTrail + Teleport Audit | CloudWatch |
| **Break-Glass 절차** | ✅ 문서화 + 승인 워크플로우 | Jira 티켓 |

---

## 10. 고객 납품 가이드

### 10.1 엔터프라이즈 고객

#### 권장 구성

| 항목 | 설정 | 이유 |
|:---|:---|:---|
| **SSH 포트** | 22022 | Port Obfuscation, 보안 감사 대응 |
| **접근 방법** | Teleport SSH (SSO 통합) | 세션 녹화, RBAC |
| **세션 녹화** | 필수 활성화 | ISMS-P, ISO 27001 대응 |
| **Break-Glass** | 승인 워크플로우 구성 | 컴플라이언스 |
| **MFA** | 필수 | 금융권 요구사항 |

#### 납품 체크리스트

- [ ] Teleport SSO 연동 (고객 IdP)
- [ ] 세션 녹화 S3 버킷 생성 (고객 계정)
- [ ] Break-Glass 절차 문서 제공
- [ ] SSH 포트 22022 설정 확인
- [ ] ISMS-P 감사 증적 템플릿 제공

### 10.2 SMB 고객

#### 권장 구성

| 항목 | 설정 | 이유 |
|:---|:---|:---|
| **SSH 포트** | 22 | 표준 포트, 운영 단순화 |
| **접근 방법** | SSM Session Manager | 라이선스 비용 없음 |
| **세션 녹화** | 선택 사항 | 비용 최적화 |
| **Break-Glass** | 간소화된 절차 | 운영 복잡도 최소화 |
| **MFA** | 선택 사항 | AWS IAM MFA |

#### 납품 체크리스트

- [ ] SSM Agent 활성화 확인
- [ ] IAM 권한 설정 (SSM 접근)
- [ ] CloudWatch Logs 설정 (선택)
- [ ] SSH 포트 22 설정 확인
- [ ] 간소화된 운영 가이드 제공

### 10.3 고객 유형별 비교

| 항목 | 엔터프라이즈 | SMB |
|:---|:---|:---|
| **SSH 포트** | 22022 | 22 |
| **접근 방법** | Teleport (SSO) | SSM |
| **세션 녹화** | 필수 | 선택 |
| **MFA** | 필수 | 선택 |
| **Break-Glass** | 승인 워크플로우 | 간소화 |
| **비용** | Teleport 라이선스 (무료) | AWS 기본 서비스 |
| **운영 복잡도** | 높음 | 낮음 |
| **보안 수준** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |

---

## 부록

### A. 참고 문서

| 문서 | 경로 |
|:---|:---|
| 종합 보안 정책 | [comprehensive-security-policy.md](comprehensive-security-policy.md) |
| Golden Image 명세서 | [golden-image-specification.md](../infrastructure/golden-image-specification.md) |
| ADR-001 접근제어 | [ADR-001-access-control-solution.md](../access-control/ADR-001-access-control-solution.md) |
| Break-Glass 절차 | [break-glass-ssh.md](../runbooks/break-glass-ssh.md) |
| 보안 최적화 가이드 | [security-optimization-best-practices.md](../access-control/security-optimization-best-practices.md) |

### B. 외부 참고 자료

- [OpenSSH Security Best Practices](https://www.ssh.com/academy/ssh/security)
- [CIS Amazon Linux 2023 Benchmark](https://www.cisecurity.org/benchmark/amazon_linux)
- [Teleport SSH Best Practices](https://goteleport.com/docs/server-access/guides/ssh-best-practices/)
- [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)

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
