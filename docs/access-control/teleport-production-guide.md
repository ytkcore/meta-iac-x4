# Teleport Community Edition 프로덕션 배포 가이드

> 고객사 납품용 상용환경 구축 완전 가이드

---

## 목차
1. [아키텍처 개요](#1-아키텍처-개요)
2. [사전 요구사항](#2-사전-요구사항)
3. [Helm Chart 배포](#3-helm-chart-배포)
4. [SSO 통합 (Google Workspace)](#4-sso-통합-google-workspace)
5. [접근 정책 설정](#5-접근-정책-설정)
6. [모니터링 및 백업](#6-모니터링-및-백업)
7. [운영 가이드](#7-운영-가이드)
8. [트러블슈팅](#8-트러블슈팅)

---

## 1. 아키텍처 개요

### 1.1 Teleport 컴포넌트

```
┌─────────────────────────────────────────────────────────────────┐
│                    Teleport Cluster Architecture                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  [외부 사용자] ── HTTPS(443) ──┐                                │
│                                 ▼                                │
│                        ┌────────────────┐                        │
│                        │ Ingress (NLB)  │                        │
│                        └────────┬───────┘                        │
│                                 ▼                                │
│                        ┌────────────────┐                        │
│                        │ Teleport Proxy │ ← 외부 진입점          │
│                        │   (Service)    │                        │
│                        └────────┬───────┘                        │
│                                 │                                │
│                                 ▼                                │
│                        ┌────────────────┐                        │
│                        │  Teleport Auth │ ← 인증/세션 관리        │
│                        │   (StatefulSet)│                        │
│                        └────────┬───────┘                        │
│                                 │                                │
│                    ┌────────────┼────────────┐                   │
│                    ▼            ▼            ▼                   │
│           ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│           │ Backend  │  │ Backend  │  │ Backend  │              │
│           │ (etcd)   │  │ (S3)     │  │ (Audit)  │              │
│           │ 상태저장  │  │ 세션녹화  │  │ 감사로그  │              │
│           └──────────┘  └──────────┘  └──────────┘              │
│                                                                  │
├──────────────────────── Target Resources ───────────────────────┤
│                                                                  │
│   [SSH Nodes]  [K8s Clusters]  [Databases]  [Web Apps]          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 HA 구성 권장 사항

| 컴포넌트 | 권장 Replicas | 리소스 요구사항 |
|:---|:---:|:---|
| **Teleport Proxy** | 3 | 2 CPU, 4GB RAM |
| **Teleport Auth** | 3 | 2 CPU, 4GB RAM |
| **etcd (Backend)** | 3 | 2 CPU, 4GB RAM, 20GB SSD |

---

## 2. 사전 요구사항

### 2.1 인프라 요구사항

| 항목 | 요구사항 |
|:---|:---|
| **Kubernetes** | v1.25 이상 |
| **Storage Class** | ReadWriteOnce 지원 (etcd용) |
| **Ingress Controller** | Nginx / AWS ALB |
| **DNS** | 와일드카드 또는 개별 레코드 |
| **TLS 인증서** | Let's Encrypt / AWS ACM |

### 2.2 도메인 설정

```bash
# 필요한 DNS 레코드
teleport.company.com       → NLB/ALB (Proxy 앞단)
*.teleport.company.com     → 동일 (Web Apps용)
```

### 2.3 필요한 도구

```bash
# 로컬 환경에 설치
kubectl v1.25+
helm v3.10+
aws-vault (AWS 환경)
```

---

## 3. Helm Chart 배포

### 3.1 Namespace 생성

```bash
kubectl create namespace teleport
```

### 3.2 Helm Repository 추가

```bash
helm repo add teleport https://charts.releases.teleport.dev
helm repo update
```

### 3.3 Values 파일 작성

**파일: `teleport-values.yaml`**

```yaml
# Teleport 클러스터 이름
clusterName: customer-cluster

# 프로덕션 모드 활성화
chartMode: standalone

# 인증 서버 설정
auth:
  replicas: 3
  resources:
    requests:
      cpu: 1000m
      memory: 2Gi
    limits:
      cpu: 2000m
      memory: 4Gi
  
  # HA를 위한 Anti-Affinity
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: app.kubernetes.io/component
            operator: In
            values:
            - auth
        topologyKey: kubernetes.io/hostname

# 프록시 서버 설정
proxy:
  replicas: 3
  resources:
    requests:
      cpu: 1000m
      memory: 2Gi
    limits:
      cpu: 2000m
      memory: 4Gi
  
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: nlb
      service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
      external-dns.alpha.kubernetes.io/hostname: teleport.company.com

# 백엔드 스토리지 (etcd)
persistence:
  enabled: true
  storageClassName: gp3  # AWS EBS gp3
  volumeSize: 20Gi

# 세션 녹화 스토리지 (S3)
sessionRecording:
  enabled: true
  backend: s3
  s3:
    region: ap-northeast-2
    bucket: customer-teleport-sessions
    # IAM Role 사용 (IRSA)
    # accessKeyId와 secretAccessKey는 비워둠

# 감사 로그 (S3)
auditLog:
  enabled: true
  backend: s3
  s3:
    region: ap-northeast-2
    bucket: customer-teleport-audit
    # IAM Role 사용

# TLS 인증서 (Let's Encrypt)
acme:
  enabled: true
  email: admin@company.com

# 로그 레벨
log:
  level: INFO
  output: json

# 고급 설정
highAvailability:
  replicaCount: 3
  certManager:
    enabled: false  # Let's Encrypt 직접 사용
```

### 3.4 AWS 리소스 생성 (Terraform)

**파일: `teleport-infra.tf`**

```hcl
# S3 버킷 - 세션 녹화
resource "aws_s3_bucket" "teleport_sessions" {
  bucket = "customer-teleport-sessions"

  tags = {
    Name        = "Teleport Session Recordings"
    Environment = "production"
  }
}

resource "aws_s3_bucket_versioning" "sessions" {
  bucket = aws_s3_bucket.teleport_sessions.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "sessions" {
  bucket = aws_s3_bucket.teleport_sessions.id

  rule {
    id     = "expire-old-sessions"
    status = "Enabled"

    expiration {
      days = 90  # 90일 후 삭제
    }
  }
}

# S3 버킷 - 감사 로그
resource "aws_s3_bucket" "teleport_audit" {
  bucket = "customer-teleport-audit"

  tags = {
    Name        = "Teleport Audit Logs"
    Environment = "production"
  }
}

resource "aws_s3_bucket_versioning" "audit" {
  bucket = aws_s3_bucket.teleport_audit.id

  versioning_configuration {
    status = "Enabled"
  }
}

# IAM Policy - Teleport Pod에 부여
resource "aws_iam_policy" "teleport_s3" {
  name        = "teleport-s3-access"
  description = "Allows Teleport to access S3 buckets for sessions and audit logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.teleport_sessions.arn}",
          "${aws_s3_bucket.teleport_sessions.arn}/*",
          "${aws_s3_bucket.teleport_audit.arn}",
          "${aws_s3_bucket.teleport_audit.arn}/*"
        ]
      }
    ]
  })
}

# IRSA (IAM Role for Service Account)
module "teleport_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "teleport-s3-access"

  oidc_providers = {
    main = {
      provider_arn               = data.aws_eks_cluster.main.identity[0].oidc[0].issuer
      namespace_service_accounts = ["teleport:teleport"]
    }
  }

  role_policy_arns = {
    s3 = aws_iam_policy.teleport_s3.arn
  }
}

output "teleport_service_account_role_arn" {
  value = module.teleport_irsa.iam_role_arn
}
```

### 3.5 Helm 배포 실행

```bash
# Terraform으로 AWS 리소스 생성
cd terraform/teleport-infra
terraform init
terraform apply

# ServiceAccount에 IAM Role 주입
ROLE_ARN=$(terraform output -raw teleport_service_account_role_arn)

# Helm Values에 IRSA 추가
cat >> teleport-values.yaml <<EOF
serviceAccount:
  create: true
  name: teleport
  annotations:
    eks.amazonaws.com/role-arn: ${ROLE_ARN}
EOF

# Helm 배포
helm install teleport teleport/teleport-cluster \
  --namespace teleport \
  --values teleport-values.yaml \
  --version 15.0.0  # 최신 stable 버전 확인
```

### 3.6 배포 확인

```bash
# Pod 상태 확인
kubectl -n teleport get pods

# 기대 결과:
# NAME                        READY   STATUS    RESTARTS   AGE
# teleport-auth-0             1/1     Running   0          5m
# teleport-auth-1             1/1     Running   0          5m
# teleport-auth-2             1/1     Running   0          5m
# teleport-proxy-0            1/1     Running   0          5m
# teleport-proxy-1            1/1     Running   0          5m
# teleport-proxy-2            1/1     Running   0          5m

# Service 확인
kubectl -n teleport get svc

# LoadBalancer 외부 IP 확인
kubectl -n teleport get svc teleport-proxy -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

---

## 4. SSO 통합 (Google Workspace)

### 4.1 Google Workspace 설정

1. **Google Admin Console** 접속
2. **앱 > 웹 및 모바일 앱 > 앱 추가 > SAML 앱 추가**
3. 앱 이름: `Teleport`
4. **다운로드**: IdP 메타데이터 XML

### 4.2 Teleport SAML 설정

```bash
# Teleport 웹 UI 접속
# https://teleport.company.com

# 초기 관리자 계정 생성 (최초 1회)
tctl users add admin --roles=editor --logins=root,ubuntu

# 이메일로 받은 링크로 접속하여 비밀번호 설정
```

**SAML Connector 생성:**

```yaml
# saml-connector.yaml
kind: saml
version: v2
metadata:
  name: google
spec:
  acs: https://teleport.company.com/v1/webapi/saml/acs
  attributes_to_roles:
    - name: groups
      value: "admin@company.com"
      roles:
        - editor
        - access
    - name: groups
      value: "developers@company.com"
      roles:
        - access
  entity_descriptor: |
    <?xml version="1.0" encoding="UTF-8"?>
    <md:EntityDescriptor xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata" 
                         entityID="https://accounts.google.com/o/saml2?idpid=...">
      <!-- Google에서 다운로드한 XML 내용 붙여넣기 -->
    </md:EntityDescriptor>
```

```bash
# SAML Connector 적용
tctl create -f saml-connector.yaml

# 확인
tctl get saml
```

### 4.3 Google에 Teleport 정보 입력

- **ACS URL**: `https://teleport.company.com/v1/webapi/saml/acs`
- **Entity ID**: `https://teleport.company.com`
- **Attribute Mapping**:
  - `email` → `email`
  - `groups` → `groups`

---

## 5. 접근 정책 설정

### 5.1 Role 정의

**파일: `roles.yaml`**

```yaml
---
# 관리자 Role
kind: role
version: v5
metadata:
  name: admin
spec:
  allow:
    logins: [root, ubuntu, admin]
    kubernetes_groups: ["system:masters"]
    kubernetes_labels:
      '*': '*'
    node_labels:
      '*': '*'
    
    # SSH 접근 허용
    rules:
      - resources: ['*']
        verbs: ['*']
    
    # K8s 접근 허용
    kubernetes_resources:
      - kind: '*'
        namespace: '*'
        name: '*'
        verbs: ['*']

---
# 개발자 Role
kind: role
version: v5
metadata:
  name: developer
spec:
  allow:
    logins: [ubuntu, {{ internal.user }}]
    kubernetes_groups: ["developers"]
    kubernetes_labels:
      env: ['dev', 'staging']
    
    # K8s 네임스페이스 제한
    kubernetes_resources:
      - kind: 'pod'
        namespace: 'development'
        name: '*'
        verbs: ['get', 'list']
      - kind: 'pod/log'
        namespace: 'development'
        name: '*'
        verbs: ['get']
  
  # 프로덕션 접근 거부
  deny:
    kubernetes_labels:
      env: 'production'

---
# 읽기 전용 Role
kind: role
version: v5
metadata:
  name: readonly
spec:
  allow:
    logins: []  # SSH 접근 불가
    kubernetes_groups: ["viewers"]
    
    kubernetes_resources:
      - kind: 'pod'
        namespace: '*'
        name: '*'
        verbs: ['get', 'list']
  
  options:
    # 세션 녹화 필수
    record_session:
      desktop: true
      ssh: true
```

```bash
# Role 적용
tctl create -f roles.yaml

# 확인
tctl get roles
```

### 5.2 사용자 초대

```bash
# 관리자 추가
tctl users add john.doe@company.com --roles=admin

# 개발자 추가
tctl users add jane.smith@company.com --roles=developer

# 읽기 전용 사용자 추가
tctl users add viewer@company.com --roles=readonly
```

---

## 6. 모니터링 및 백업

### 6.1 Prometheus 메트릭 노출

```yaml
# prometheus-servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: teleport
  namespace: teleport
spec:
  selector:
    matchLabels:
      app: teleport
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
```

### 6.2 주요 메트릭

| 메트릭 | 설명 | Alert 조건 |
|:---|:---|:---|
| `teleport_connected_resources` | 연결된 리소스 수 | < 1 (30분 이상) |
| `teleport_sessions_active` | 활성 세션 수 | > 100 (부하) |
| `teleport_audit_failed_emit_events` | 감사 로그 실패 | > 0 |
| `process_cpu_seconds_total` | CPU 사용률 | > 80% |

### 6.3 etcd 백업

```bash
# CronJob으로 etcd 백업
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: teleport-etcd-backup
  namespace: teleport
spec:
  schedule: "0 2 * * *"  # 매일 02:00
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: teleport
          containers:
          - name: backup
            image: public.ecr.aws/gravitational/teleport:15
            command:
            - /bin/sh
            - -c
            - |
              tctl auth export > /backup/teleport-backup-\$(date +%Y%m%d).yaml
              aws s3 cp /backup/ s3://customer-teleport-backup/ --recursive
            volumeMounts:
            - name: backup
              mountPath: /backup
          volumes:
          - name: backup
            emptyDir: {}
          restartPolicy: OnFailure
EOF
```

---

## 7. 운영 가이드

### 7.1 일상 운영 작업

**사용자 목록 조회:**
```bash
tctl users ls
```

**활성 세션 확인:**
```bash
tctl sessions ls
```

**세션 녹화 재생:**
```bash
# Web UI에서: https://teleport.company.com/web/cluster/sessions
```

**인증서 갱신 확인:**
```bash
tctl auth sign --format=x509 --out=teleport
openssl x509 -in teleport -text -noout | grep "Not After"
```

### 7.2 버전 업그레이드

```bash
# Helm Chart 업데이트
helm repo update

# 새 버전 확인
helm search repo teleport/teleport-cluster

# 백업 수행 (필수!)
kubectl -n teleport exec teleport-auth-0 -- tctl auth export > backup.yaml

# 업그레이드
helm upgrade teleport teleport/teleport-cluster \
  --namespace teleport \
  --values teleport-values.yaml \
  --version 15.1.0

# Pod 재시작 확인
kubectl -n teleport get pods -w
```

---

## 8. 트러블슈팅

### 8.1 Pod가 시작하지 않음

```bash
# 로그 확인
kubectl -n teleport logs teleport-auth-0

# 일반적인 원인:
# 1. S3 접근 권한 없음 → IRSA 확인
# 2. etcd 볼륨 마운트 실패 → PVC 상태 확인
# 3. 메모리 부족 → 리소스 늘리기
```

### 8.2 SSO 로그인 실패

```bash
# Auth 로그에서 SAML 관련 에러 확인
kubectl -n teleport logs -l app.kubernetes.io/component=auth | grep SAML

# 일반적인 원인:
# 1. ACS URL 불일치
# 2. Attribute mapping 오류
# 3. Google Workspace 앱 비활성화
```

### 8.3 세션 녹화가 저장되지 않음

```bash
# S3 버킷 권한 확인
aws s3 ls s3://customer-teleport-sessions/

# IAM Role 확인
kubectl -n teleport describe sa teleport

# 일반적인 원인:
# 1. IRSA 미설정
# 2. S3 버킷 정책 오류
# 3. 리전 불일치
```

---

## 참고 자료

- [Teleport Official Documentation](https://goteleport.com/docs/)
- [Helm Chart Reference](https://github.com/gravitational/teleport/tree/master/examples/chart/teleport-cluster)
- [Production Checklist](https://goteleport.com/docs/production/)
