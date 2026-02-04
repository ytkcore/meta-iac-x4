# Teleport 운영 매뉴얼

> EC2 기반 Teleport 클러스터의 일상 운영 및 관리 가이드

---

## 목차

1. [초기 설정 (Bootstrap)](#1-초기-설정-bootstrap)
2. [일상 사용 (개발자용)](#2-일상-사용-개발자용)
3. [관리 작업 (Admin용)](#3-관리-작업-admin용)
4. [트러블슈팅](#4-트러블슈팅)

---

## 1. 초기 설정 (Bootstrap)

### 1.1 최초 관리자 생성

Teleport 배포 직후, 최초 관리자 계정을 생성해야 합니다.

```bash
# 1. Teleport 인스턴스 ID 확인
INSTANCE_ID=$(aws-vault exec devops -- \
  terraform -chdir=stacks/dev/15-teleport output -json instance_ids | jq -r '.[0]')

# 2. SSM으로 접속
aws-vault exec devops -- aws ssm start-session --target $INSTANCE_ID

# 3. 인스턴스 내에서 관리자 생성
sudo tctl users add admin \
  --roles=editor,access \
  --logins=root,ubuntu,ec2-user
```

**출력 예시:**
```
User "admin" has been created but requires a password. Share this URL with the user to complete user setup, link is valid for 1h:
https://teleport.dev.unifiedmeta.net:443/web/invite/abc123...
```

> [!IMPORTANT]
> 초대 URL은 **1시간 유효**합니다. 즉시 브라우저에서 열어 비밀번호와 OTP를 설정하세요.

### 1.2 Kubernetes Agent 설정

RKE2 클러스터에 Teleport Kube Agent를 배포하려면 조인 토큰이 필요합니다.

#### Option A: Static Token (간단, 개발용)

```bash
# Teleport 서버에서 토큰 생성
sudo tctl tokens add --type=kube --ttl=8760h
# 출력: f8e1c2a3b4d5e6f7...

# K8s Secret 생성
kubectl create secret generic teleport-kube-agent-join-token \
  -n teleport \
  --from-literal=auth-token='f8e1c2a3b4d5e6f7...'

# ArgoCD에서 teleport-agent 앱 Sync
```

#### Option B: IAM Join (권장, 프로덕션용)

```bash
# Teleport 서버에서 IAM Join 토큰 생성
sudo tctl tokens add \
  --type=kube \
  --method=iam \
  --aws-account=599913747911 \
  --aws-arn=arn:aws:sts::599913747911:assumed-role/dev-meta-k8s-role/*
```

`teleport-agent.yaml` 수정:
```yaml
joinParams:
  method: iam
  token_name: kube-iam-token
```

### 1.3 접속 확인

```bash
# 로컬 PC에서 tsh 설치
brew install teleport  # macOS
# 또는 https://goteleport.com/download/

# 로그인
tsh login --proxy=teleport.dev.unifiedmeta.net:443 --user=admin

# K8s 클러스터 확인
tsh kube ls

# 클러스터 로그인
tsh kube login meta-dev

# kubectl 사용
kubectl get nodes
```

---

## 2. 일상 사용 (개발자용)

### 2.1 tsh CLI 기본 명령어

#### 로그인/로그아웃

```bash
# 로그인 (브라우저 SSO 팝업)
tsh login --proxy=teleport.dev.unifiedmeta.net

# 상태 확인
tsh status

# 로그아웃
tsh logout
```

#### 서버 접속 (SSH)

```bash
# 접근 가능한 서버 목록
tsh ls

# SSH 접속
tsh ssh ubuntu@postgres.dev.unifiedmeta.net

# 파일 복사
tsh scp ubuntu@postgres:/var/log/app.log ./local.log
```

#### Kubernetes 접근

```bash
# 클러스터 목록
tsh kube ls

# 클러스터 로그인 (kubeconfig 자동 설정)
tsh kube login meta-dev

# kubectl 사용 (Teleport 경유)
kubectl get pods -A
kubectl logs -f deployment/my-app

# 클러스터 전환
tsh kube login meta-prod
```

#### Database 접근

```bash
# DB 목록
tsh db ls

# PostgreSQL 접속
tsh db connect postgres --db-user=admin --db-name=mydb

# 로컬 프록시 (기존 툴 사용)
tsh proxy db postgres --port=15432 &
psql -h localhost -p 15432 -U admin mydb
```

### 2.2 인증서 갱신

Teleport 인증서는 **12시간 유효**합니다.

```bash
# 만료 시간 확인
tsh status

# 갱신 (재로그인)
tsh login --proxy=teleport.dev.unifiedmeta.net
```

---

## 3. 관리 작업 (Admin용)

### 3.1 사용자 관리

#### 사용자 추가

```bash
# 개발자 추가 (읽기/쓰기 권한)
tctl users add john.doe@company.com \
  --roles=access \
  --logins=ubuntu,ec2-user

# 관리자 추가
tctl users add admin@company.com \
  --roles=editor,access \
  --logins=root,ubuntu,ec2-user
```

#### 사용자 목록/삭제

```bash
# 목록
tctl users ls

# 삭제
tctl users rm john.doe@company.com

# 비밀번호 재설정 (초대 링크 재발급)
tctl users reset john.doe@company.com
```

### 3.2 역할(Role) 관리

기본 제공 Role:
- `editor`: 모든 관리 권한
- `access`: SSH/K8s 접근 권한
- `auditor`: 읽기 전용 + 감사 로그 조회

#### 커스텀 Role 생성

```yaml
# dev-role.yaml
kind: role
version: v5
metadata:
  name: developer
spec:
  allow:
    # SSH 로그인 계정
    logins: [ubuntu, "{{internal.user}}"]
    
    # K8s 그룹
    kubernetes_groups: [developers]
    
    # 접근 가능한 서버 (라벨 기반)
    node_labels:
      env: [dev, staging]
    
    # K8s 리소스 제한
    kubernetes_resources:
      - kind: pod
        namespace: development
        name: "*"
        verbs: [get, list]
      - kind: pod/log
        namespace: development
        name: "*"
        verbs: [get]
  
  deny:
    # 프로덕션 접근 차단
    node_labels:
      env: production
```

```bash
# Role 적용
tctl create -f dev-role.yaml

# Role 목록
tctl get roles

# Role 삭제
tctl rm role/developer
```

### 3.3 노드/리소스 등록

#### SSH 노드 등록 (Golden Image Auto)

Golden Image에 Teleport Agent가 포함되어 있으면 자동 등록됩니다.

수동 확인:
```bash
# 등록된 노드 목록
tctl nodes ls

# 노드 상세 정보
tctl get node/<node-id>
```

#### Kubernetes 클러스터 등록

ArgoCD로 `teleport-agent.yaml` 배포 시 자동 등록됩니다.

확인:
```bash
# 등록된 K8s 클러스터
tctl get kube_cluster

# 연결 상태 확인
tctl status
```

### 3.4 세션 관리

#### 활성 세션 조회

```bash
# 현재 활성 세션
tctl get sessions

# 특정 사용자 세션
tctl get sessions --format=json | jq '.[] | select(.user=="john.doe@company.com")'
```

#### 세션 강제 종료

```bash
# 세션 ID로 종료
tctl rm session/<session-id>
```

#### 세션 녹화 재생

```bash
# Web UI에서 확인 (권장)
# https://teleport.dev.unifiedmeta.net/web/cluster/sessions

# CLI로 재생
tsh play <session-id>
```

### 3.5 감사 로그

```bash
# 최근 이벤트 조회
tctl get events --type=session.start --format=json | jq

# 특정 사용자 액션 조회
tctl get events --type=session.start --format=json | \
  jq '.[] | select(.user=="john.doe@company.com")'

# S3에서 직접 조회 (장기 보관)
aws s3 ls s3://dev-meta-teleport-sessions-ap-northeast-2-599913747911/records/
```

---

## 4. 트러블슈팅

### 4.1 로그인 실패

#### 증상: `tsh login` 시 연결 실패

```bash
# DNS 확인
dig teleport.dev.unifiedmeta.net

# ALB 상태 확인
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn>

# Teleport 서비스 상태 (SSM 접속 후)
sudo systemctl status teleport
sudo journalctl -u teleport -f
```

#### 증상: SSO 리디렉션 실패

- 브라우저 쿠키/캐시 삭제
- 시크릿 모드로 재시도
- Teleport 서버 로그 확인: `/var/log/user-data.log`

### 4.2 Kubernetes Agent 연결 실패

```bash
# ArgoCD에서 상태 확인
kubectl get applications -n argocd teleport-agent

# Agent Pod 로그
kubectl logs -n teleport -l app=teleport-kube-agent

# 일반적인 원인
# 1. 토큰 만료 또는 잘못됨 → Secret 재생성
# 2. Teleport 서버 unreachable → 네트워크 확인
# 3. RBAC 권한 부족 → ServiceAccount 확인
```

### 4.3 SSH 세션 끊김

#### 증상: tsh ssh 접속 후 바로 끊김

```bash
# 노드 상태 확인
tctl nodes ls

# 특정 노드 연결 테스트
tsh ssh -vvv ubuntu@node-name

# Agent 상태 (해당 노드에서)
sudo systemctl status teleport
```

### 4.4 인증서 만료

```bash
# 인증서 상태 확인
tsh status

# 수동 갱신
tsh login --proxy=teleport.dev.unifiedmeta.net

# 갱신 실패 시 캐시 삭제
rm -rf ~/.tsh/*
tsh login --proxy=teleport.dev.unifiedmeta.net
```

### 4.5 성능 문제

#### 증상: 세션 연결이 느림

```bash
# Teleport 서버 리소스 확인 (SSM)
top
df -h

# DynamoDB 스로틀링 확인
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name UserErrors \
  --dimensions Name=TableName,Value=dev-meta-teleport-backend \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T23:59:59Z \
  --period 3600 \
  --statistics Sum

# HA 모드 활성화 고려
# terraform.tfvars
enable_ha = true
```

### 4.6 Break Glass (비상 접근)

Teleport가 완전히 다운되었을 때:

```bash
# Option A: AWS SSM (권장)
aws ssm start-session --target i-xxxxxxxxx

# Option B: SSH 직접 접속 (최후 수단)
# 1. Console에서 임시 SG 생성 (Port 22 허용)
# 2. EC2에 연결
# 3. SG 즉시 제거
```

---

## 부록

### A. 자주 사용하는 tctl 명령어

| 명령 | 설명 |
|:---|:---|
| `tctl status` | 클러스터 상태 확인 |
| `tctl users ls` | 사용자 목록 |
| `tctl nodes ls` | 등록된 노드 목록 |
| `tctl get kube_cluster` | K8s 클러스터 목록 |
| `tctl get sessions` | 활성 세션 |
| `tctl get events` | 감사 로그 |

### B. 관련 문서

| 문서 | 설명 |
|:---|:---|
| [teleport-ec2-deployment-guide.md](teleport-ec2-deployment-guide.md) | 배포 가이드 |
| [security-optimization-best-practices.md](security-optimization-best-practices.md) | 보안 최적화 |
| [ADR-001-access-control-solution.md](ADR-001-access-control-solution.md) | 아키텍처 결정 |

### C. 공식 문서

- [Teleport Documentation](https://goteleport.com/docs/)
- [tsh CLI Reference](https://goteleport.com/docs/reference/cli/tsh/)
- [tctl Admin Guide](https://goteleport.com/docs/reference/cli/tctl/)
