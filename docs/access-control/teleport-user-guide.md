# Teleport 사용 가이드 (Teleport User Guide)

> **Meta Infrastructure Platform 텔레포트 완전 가이드**  
> **최종 업데이트**: 2026-02-04  
> **대상**: DevOps 엔지니어, 시스템 관리자

---

## 📋 목차

1. [텔레포트란?](#1-텔레포트란)
2. [아키텍처 개요](#2-아키텍처-개요)
3. [초기 설정 (관리자)](#3-초기-설정-관리자)
4. [일상 사용법 (사용자)](#4-일상-사용법-사용자)
5. [고급 사용법](#5-고급-사용법)
6. [Break-Glass 비상 접근](#6-break-glass-비상-접근)
7. [문제 해결](#7-문제-해결)

---

## 1. 텔레포트란?

### 1.1 핵심 개념

**Teleport**는 SSH, Kubernetes, Database, Web Application에 대한 **Zero Trust 통합 접근 제어 플랫폼**입니다.

#### 기존 SSH vs Teleport

| 항목 | 기존 SSH | Teleport |
|:---|:---|:---|
| **인증** | 정적 SSH 키 (분실/유출 위험) | SSO + MFA + 단기 인증서 (12시간) |
| **접근 제어** | `~/.ssh/authorized_keys` 수동 관리 | 중앙화된 RBAC |
| **감사 로그** | `/var/log/auth.log` (명령어 미기록) | **세션 녹화** (영상처럼 재생 가능) |
| **다중 프로토콜** | SSH만 지원 | SSH + K8s + DB + Web Apps |
| **네트워크** | 22번 포트 직접 노출 | ALB + WAF 보호 |

### 1.2 왜 텔레포트를 사용하는가?

> [!IMPORTANT]
> **보안 컴플라이언스 필수 요구사항**
> - **ISMS-P**: 모든 접근 기록 1년 보관 의무
> - **ISO 27001**: MFA 및 세션 녹화 필수
> - **고객사 감사**: "누가 언제 무엇을 했는지" 증명 필요

#### 실제 사례

```
❌ 기존 방식 (SSH 키)
- 퇴사자 키 회수 어려움 → 보안 사고 위험
- 새벽 3시 장애 시 VPN 연결 실패 → 복구 지연
- 감사 시 "이 명령어 누가 입력했나요?" → 추적 불가

✅ Teleport 도입 후
- 퇴사자 계정 즉시 비활성화 (SSO 연동)
- AWS SSM Break-Glass로 VPN 없이 접근
- 세션 녹화로 모든 명령어 영상 재생 가능
```

---

## 2. 아키텍처 개요

### 2.1 구성 요소

```
┌─────────────────────────────────────────────────────────────────┐
│                    Internet (사용자)                             │
└────────────────────────┬────────────────────────────────────────┘
                         │ HTTPS (443)
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  AWS WAF (20-waf)                                                │
│  └─ Rate Limiting, OWASP Top 10 차단                             │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  Public ALB (15-teleport)                                        │
│  ├─ ACM 인증서 (teleport.unifiedmeta.net)                       │
│  └─ TLS 종료 → 3080 포트로 전달                                 │
└────────────────────────┬────────────────────────────────────────┘
                         │ HTTP (3080)
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  Teleport EC2 Instances (HA: 2개)                                │
│  ├─ AZ-a: t3.small (10-golden-image 기반)                       │
│  ├─ AZ-c: t3.small (10-golden-image 기반)                       │
│  └─ 역할: Auth + Proxy + Node (All-in-One)                      │
└────────────────────────┬────────────────────────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        ▼                ▼                ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  DynamoDB    │  │  S3 Bucket   │  │  Target EC2  │
│  (클러스터   │  │  (세션 녹화) │  │  (SSH 대상)  │
│   상태 저장) │  │              │  │              │
└──────────────┘  └──────────────┘  └──────────────┘
```

### 2.2 스택 구성

| 스택 | 역할 | 주요 리소스 |
|:---|:---|:---|
| **10-golden-image** | 기본 AMI 제공 | Packer 빌드 AMI (Teleport Agent 사전 설치) |
| **15-teleport** | Teleport 서버 배포 | EC2 (HA 2대), ALB, ACM, Route53 |
| **20-waf** | 웹 방화벽 | AWS WAF ACL (Rate Limiting) |

---

## 3. 초기 설정 (관리자)

### 3.1 배포 확인

```bash
# 1. Teleport 스택 배포 상태 확인
cd /Users/ytkcloud/cloud/meta
aws-vault exec devops -- make plan ENV=dev STACK=15-teleport

# 2. 인스턴스 ID 확인
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*teleport*" \
  --query "Reservations[*].Instances[*].[InstanceId,State.Name,PrivateIpAddress]" \
  --output table
```

### 3.2 최초 관리자 계정 생성

> [!WARNING]
> **SSM을 통한 초기 설정 필수**  
> Teleport는 최초 배포 시 관리자 계정이 없으므로, AWS SSM으로 접속하여 생성해야 합니다.

```bash
# 1. 인스턴스 ID 확인
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*teleport*" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text)

echo "Teleport Instance ID: $INSTANCE_ID"

# 2. SSM 세션 시작
aws ssm start-session --target $INSTANCE_ID

# 3. Teleport 관리자 계정 생성 (SSM 세션 내부)
sudo tctl users add admin --roles=editor,access --logins=ec2-user,ubuntu

# 출력 예시:
# User "admin" has been created but requires a password. Share this URL with the user to complete user setup, link is valid for 1h:
# https://teleport.unifiedmeta.net:443/web/invite/abc123xyz
```

> [!TIP]
> **초대 링크 유효 시간: 1시간**  
> 링크를 복사하여 브라우저에서 열고, 비밀번호 및 MFA(Google Authenticator 등) 설정을 완료하세요.

### 3.3 SSO 연동 (선택 사항)

#### Google Workspace 연동 예시

```bash
# SSM 세션 내부에서 실행
sudo tee /etc/teleport.yaml > /dev/null <<EOF
auth_service:
  authentication:
    type: saml
    second_factor: on
  connectors:
  - kind: saml
    version: v2
    metadata:
      name: google
    spec:
      provider: google
      acs: https://teleport.unifiedmeta.net/v1/webapi/saml/acs
      entity_descriptor_url: https://accounts.google.com/o/saml2/idp?idpid=YOUR_IDP_ID
      attributes_to_roles:
      - name: "groups"
        value: "devops@example.com"
        roles: ["editor", "access"]
EOF

# Teleport 재시작
sudo systemctl restart teleport
```

---

## 4. 일상 사용법 (사용자)

### 4.1 tsh 클라이언트 설치

#### macOS

```bash
# Homebrew로 설치
brew install teleport

# 버전 확인
tsh version
```

#### Linux

```bash
# Ubuntu/Debian
curl https://apt.releases.teleport.dev/gpg | sudo apt-key add -
sudo add-apt-repository 'deb https://apt.releases.teleport.dev/ stable main'
sudo apt update
sudo apt install teleport

# RHEL/CentOS
sudo yum-config-manager --add-repo https://rpm.releases.teleport.dev/teleport.repo
sudo yum install teleport
```

### 4.2 로그인

```bash
# 1. Teleport 클러스터 로그인
tsh login --proxy=teleport.unifiedmeta.net --user=your-email@example.com

# 2. MFA 입력 (Google Authenticator 등)
# 3. 브라우저가 자동으로 열리며 SSO 인증 진행
```

### 4.3 SSH 접속

#### 사용 가능한 노드 목록 확인

```bash
tsh ls

# 출력 예시:
# Node Name        Address        Labels
# ---------------- -------------- -------------------------
# bastion-dev      10.0.1.10:3022 env=dev,role=bastion
# harbor-dev       10.0.2.20:3022 env=dev,role=harbor
# db-primary-dev   10.0.3.30:3022 env=dev,role=database
```

#### SSH 접속

```bash
# 기본 접속
tsh ssh ec2-user@bastion-dev

# 특정 명령어 실행
tsh ssh ec2-user@harbor-dev "docker ps"

# 파일 복사 (SCP)
tsh scp myfile.txt ec2-user@bastion-dev:/tmp/
```

### 4.4 Kubernetes 접속

```bash
# 1. 사용 가능한 클러스터 확인
tsh kube ls

# 2. 클러스터 로그인
tsh kube login rke2-dev

# 3. kubectl 명령어 사용
kubectl get nodes
kubectl get pods -A
```

### 4.5 Database 접속

```bash
# 1. 사용 가능한 DB 확인
tsh db ls

# 2. DB 연결
tsh db connect postgres-dev --db-user=admin --db-name=mydb

# 3. 로컬 프록시 모드 (psql 등 네이티브 클라이언트 사용)
tsh db proxy postgres-dev --db-user=admin --port=5432
# 다른 터미널에서:
psql -h localhost -p 5432 -U admin -d mydb
```

---

## 5. 고급 사용법

### 5.1 세션 녹화 확인 (관리자)

```bash
# 웹 UI에서 확인
# https://teleport.unifiedmeta.net/web/cluster/sessions

# CLI로 세션 목록 조회
tsh recordings ls

# 특정 세션 재생
tsh play <session-id>
```

### 5.2 접근 요청 (Access Request)

```bash
# 1. 특정 역할 요청
tsh request create --roles=dba

# 2. 요청 상태 확인
tsh request ls

# 3. 승인 대기 중 알림 (Slack 연동 시)
# 관리자가 Slack에서 승인 버튼 클릭

# 4. 승인 후 로그인
tsh login --request-id=<request-id>
```

### 5.3 포트 포워딩

```bash
# 로컬 8080 → 원격 80 포워딩
tsh ssh -L 8080:localhost:80 ec2-user@harbor-dev

# 브라우저에서 http://localhost:8080 접속
```

---

## 6. Break-Glass 비상 접근

### 6.1 시나리오: Teleport 장애 시 긴급 접근

> [!CAUTION]
> **Break-Glass는 최후의 수단**  
> 모든 작업은 Jira 티켓 또는 Slack Incident로 기록해야 합니다.

#### 방법 1: AWS SSM (권장)

```bash
# 1. 대상 인스턴스 ID 확인
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*bastion*" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text

# 2. SSM 세션 시작
aws ssm start-session --target i-0123456789abcdef0

# 3. 작업 수행 후 즉시 종료
exit
```

#### 방법 2: Direct SSH (극히 제한적)

```bash
# 1. Jira 티켓 생성 (필수)
# 2. Security Group 임시 규칙 추가
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxxx \
  --protocol tcp \
  --port 22 \
  --cidr YOUR_IP/32

# 3. SSH 접속
ssh -i ~/.ssh/your-key.pem ec2-user@10.0.1.10

# 4. 작업 완료 후 즉시 규칙 삭제
aws ec2 revoke-security-group-ingress \
  --group-id sg-xxxxxxxxx \
  --protocol tcp \
  --port 22 \
  --cidr YOUR_IP/32
```

---

## 7. 문제 해결

### 7.1 "tsh login" 실패

#### 증상
```
ERROR: failed to connect to proxy: connection refused
```

#### 해결 방법

```bash
# 1. 프록시 주소 확인
nslookup teleport.unifiedmeta.net

# 2. ALB 상태 확인
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:...

# 3. Teleport 서비스 상태 확인 (SSM으로 접속)
sudo systemctl status teleport
sudo journalctl -u teleport -n 50
```

### 7.2 "tsh ssh" 연결 실패

#### 증상
```
ERROR: ssh: rejected: administratively prohibited (open failed)
```

#### 해결 방법

```bash
# 1. 노드가 Teleport에 등록되었는지 확인
tsh ls | grep your-node-name

# 2. 대상 EC2에서 Teleport Agent 상태 확인 (SSM)
sudo systemctl status teleport
sudo journalctl -u teleport -n 50

# 3. Security Group 확인 (Teleport 3022 포트)
aws ec2 describe-security-groups --group-ids sg-xxxxxxxxx
```

### 7.3 세션 녹화가 재생되지 않음

#### 증상
```
ERROR: failed to fetch session: not found
```

#### 해결 방법

```bash
# 1. S3 버킷 확인
aws s3 ls s3://your-teleport-recordings-bucket/

# 2. Teleport 설정 확인 (SSM)
sudo cat /etc/teleport.yaml | grep -A 5 "session_recording"

# 3. IAM 역할 권한 확인
aws iam get-role-policy --role-name teleport-ec2-role --policy-name s3-access
```

---

## 📚 추가 자료

### 공식 문서
- [Teleport 공식 문서](https://goteleport.com/docs/)
- [Teleport GitHub](https://github.com/gravitational/teleport)

### 내부 문서
- [Teleport EC2 배포 가이드](./teleport-ec2-deployment-guide.md)
- [Teleport 운영 매뉴얼](./teleport-operations-manual.md)
- [Teleport 프로덕션 가이드](./teleport-production-guide.md)
- [보안 최적화 모범 사례](./security-optimization-best-practices.md)

### 관련 스택
- [15-teleport/main.tf](../../stacks/dev/15-teleport/main.tf)
- [modules/teleport-ec2](../../modules/teleport-ec2)

---

## 🎯 Quick Reference

### 자주 사용하는 명령어

```bash
# 로그인
tsh login --proxy=teleport.unifiedmeta.net

# 노드 목록
tsh ls

# SSH 접속
tsh ssh ec2-user@node-name

# 파일 복사
tsh scp file.txt ec2-user@node:/path/

# Kubernetes 접속
tsh kube login cluster-name
kubectl get pods

# 세션 기록 확인
tsh recordings ls
tsh play <session-id>

# 로그아웃
tsh logout
```

### 접근 우선순위

1. **1순위**: Teleport SSH (`tsh ssh`) - 일상 운영
2. **2순위**: AWS SSM - Teleport 장애 시
3. **3순위**: Direct SSH - 극히 제한적 (Jira 티켓 필수)

---

**문의**: Platform Team  
**마지막 업데이트**: 2026-02-04
