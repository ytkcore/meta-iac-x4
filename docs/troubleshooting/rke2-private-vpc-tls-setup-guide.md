# Private VPC RKE2 클러스터 TLS 인증서 설정 가이드

> **버전**: 1.0  
> **대상**: AWS Private VPC에 배포된 RKE2 Kubernetes 클러스터  
> **목적**: Let's Encrypt를 사용한 TLS 인증서 자동 발급 및 관리

---

## 목차

1. [개요](#개요)
2. [아키텍처](#아키텍처)
3. [사전 요구사항](#사전-요구사항)
4. [구성 단계](#구성-단계)
5. [검증](#검증)
6. [트러블슈팅](#트러블슈팅)

---

## 개요

### 왜 DNS-01 Challenge인가?

Private VPC 환경에서 Let's Encrypt TLS 인증서를 발급받을 때, 표준 HTTP-01 Challenge는 **Hairpin Routing 문제**로 인해 작동하지 않습니다.

| Challenge 방식 | Public 환경 | Private VPC 환경 |
|---------------|-------------|------------------|
| HTTP-01 | ✅ 작동 | ❌ Hairpin 문제 |
| DNS-01 | ✅ 작동 | ✅ 작동 |

### 핵심 원리

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    인증서 발급 시 Zone 역할 분리                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌──────────────────────────────┐  ┌──────────────────────────────┐       │
│   │    PUBLIC Zone               │  │    PRIVATE Zone              │       │
│   │    (인터넷에서 조회 가능)     │  │    (VPC 내부 전용)           │       │
│   ├──────────────────────────────┤  ├──────────────────────────────┤       │
│   │                              │  │                              │       │
│   │  용도:                        │  │  용도:                        │       │
│   │  • Let's Encrypt 검증용      │  │  • 내부 DNS 라우팅            │       │
│   │  • DNS-01 TXT 레코드         │  │  • Teleport → 앱 연결         │       │
│   │                              │  │  • External-DNS 등록          │       │
│   │                              │  │                              │       │
│   │  _acme-challenge.app.xxx     │  │  argocd.xxx → NLB IP         │       │
│   │  (자동 생성/삭제)             │  │  grafana.xxx → NLB IP        │       │
│   │                              │  │                              │       │
│   └──────────────────────────────┘  └──────────────────────────────┘       │
│                                                                             │
│   Let's Encrypt는 인터넷에서 PUBLIC Zone만 확인 가능                        │
│   Private Zone은 VPC 내부에서만 접근 가능                                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 아키텍처

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         전체 TLS 인증서 흐름                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                           ┌─────────────────────┐                           │
│                           │   Let's Encrypt     │                           │
│                           │   ACME Server       │                           │
│                           └──────────┬──────────┘                           │
│                                      │                                      │
│                              2️⃣ DNS 조회                                    │
│                                      ▼                                      │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                     Route53 PUBLIC Zone                              │  │
│   │                                                                      │  │
│   │   _acme-challenge.grafana.unifiedmeta.net  TXT "xxx..."             │  │
│   │                                                                      │  │
│   └───────────────────────────────▲─────────────────────────────────────┘  │
│                                   │                                         │
│                           1️⃣ TXT 레코드 생성                                │
│                                   │                                         │
│   ┌───────────────────────────────┴─────────────────────────────────────┐  │
│   │                        VPC (Private)                                 │  │
│   │                                                                      │  │
│   │   ┌─────────────────────────────────────────────────────────────┐   │  │
│   │   │                    RKE2 Cluster                              │   │  │
│   │   │                                                              │   │  │
│   │   │   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    │   │  │
│   │   │   │ cert-manager│───▶│ ClusterIssuer│───▶│ Certificate │    │   │  │
│   │   │   │             │    │ (DNS-01)    │    │ (TLS Secret)│    │   │  │
│   │   │   └─────────────┘    └─────────────┘    └──────┬──────┘    │   │  │
│   │   │                                                │           │   │  │
│   │   │                                        3️⃣ TLS 인증서       │   │  │
│   │   │                                                ▼           │   │  │
│   │   │   ┌─────────────────────────────────────────────────────┐   │   │  │
│   │   │   │              Ingress Controller (nginx)              │   │   │  │
│   │   │   │                                                      │   │   │  │
│   │   │   │   grafana.xxx    argocd.xxx    longhorn.xxx         │   │   │  │
│   │   │   │                                                      │   │   │  │
│   │   │   └──────────────────────────────────────────────────────┘   │   │  │
│   │   │                                                              │   │  │
│   │   └──────────────────────────────────────────────────────────────┘   │  │
│   │                                                                      │  │
│   └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 사전 요구사항

### 1. AWS 리소스

| 리소스 | 설명 | 필수 여부 |
|--------|------|----------|
| Route53 Public Hosted Zone | Let's Encrypt 검증용 | ✅ 필수 |
| Route53 Private Hosted Zone | 내부 DNS 라우팅용 | ✅ 필수 |
| RKE2 노드 IAM Role | Route53 API 접근용 | ✅ 필수 |

### 2. Kubernetes 컴포넌트

| 컴포넌트 | 버전 | 용도 |
|----------|------|------|
| cert-manager | v1.13+ | 인증서 자동화 |
| nginx-ingress | - | TLS 종료 |
| external-dns | - | DNS 레코드 자동 관리 (선택) |

### 3. IAM 권한 (글로벌 필수)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CertManagerDNS01TXTRecords",
      "Effect": "Allow",
      "Action": ["route53:ChangeResourceRecordSets"],
      "Resource": "arn:aws:route53:::hostedzone/PUBLIC_ZONE_ID"
    },
    {
      "Sid": "CertManagerDNS01ChangeVerification",
      "Effect": "Allow",
      "Action": ["route53:GetChange"],
      "Resource": "arn:aws:route53:::change/*"
    },
    {
      "Sid": "CertManagerDNS01ZoneDiscovery",
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets",
        "route53:ListHostedZonesByName"
      ],
      "Resource": "*"
    }
  ]
}
```

#### 권한별 필요 이유

| 권한 | 필수 | 용도 |
|------|------|------|
| `route53:ChangeResourceRecordSets` | ✅ | TXT 레코드 생성/삭제 |
| `route53:GetChange` | ✅ | DNS 전파 완료 확인 (PENDING→INSYNC) |
| `route53:ListHostedZones` | ⚪ | Zone ID 자동 탐색 |
| `route53:ListResourceRecordSets` | ⚪ | 기존 레코드 충돌 방지 |

> ⚠️ **주의**: `route53:GetChange` 없이는 cert-manager가 DNS 전파 완료를 확인할 수 없어 Challenge가 영원히 pending 상태로 유지됩니다.

---

## 구성 단계

### Step 1: cert-manager 설치

```yaml
# gitops-apps/bootstrap/cert-manager.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
  namespace: argocd
spec:
  source:
    repoURL: https://charts.jetstack.io
    targetRevision: v1.13.3
    chart: cert-manager
    helm:
      values: |
        installCRDs: true
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
  destination:
    server: https://kubernetes.default.svc
    namespace: cert-manager
```

### Step 2: ClusterIssuer 설정 (DNS-01)

```yaml
# gitops-apps/bootstrap/issuers/cluster-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: devops@your-domain.com
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
    - dns01:
        route53:
          region: ap-northeast-2
          hostedZoneID: YOUR_PUBLIC_ZONE_ID
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: devops@your-domain.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - dns01:
        route53:
          region: ap-northeast-2
          hostedZoneID: YOUR_PUBLIC_ZONE_ID
```

### Step 3: IAM 정책 추가 (Terraform)

```hcl
# stacks/dev/50-rke2/main.tf

resource "aws_iam_policy" "cert_manager_dns01" {
  count       = var.base_domain != "" ? 1 : 0
  name        = "${var.env}-${var.project}-cert-manager-dns01"
  description = "Permissions for cert-manager DNS-01 challenge with Route53"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = "arn:aws:route53:::hostedzone/${data.aws_route53_zone.public[0].zone_id}"
      },
      {
        Effect   = "Allow"
        Action   = ["route53:GetChange"]
        Resource = "arn:aws:route53:::change/*"
      },
      {
        Effect   = "Allow"
        Action   = ["route53:ListHostedZones", "route53:ListResourceRecordSets"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cert_manager_dns01" {
  count      = var.base_domain != "" ? 1 : 0
  role       = module.rke2.iam_role_name
  policy_arn = aws_iam_policy.cert_manager_dns01[0].arn
}
```

### Step 4: Ingress에 TLS 설정

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  namespace: monitoring
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - grafana.your-domain.com
      secretName: grafana-tls
  rules:
    - host: grafana.your-domain.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: grafana
                port:
                  number: 80
```

---

## 검증

### 1. ClusterIssuer 상태 확인

```bash
kubectl get clusterissuer
# NAME                  READY   AGE
# letsencrypt-prod      True    5m
# letsencrypt-staging   True    5m
```

### 2. Certificate 상태 확인

```bash
kubectl get certificates -A
# NAMESPACE    NAME          READY   SECRET        AGE
# monitoring   grafana-tls   True    grafana-tls   2m
```

### 3. Challenge 진행 확인

```bash
kubectl get challenges -A
# (발급 완료 시 challenges가 없어야 함)
```

### 4. TXT 레코드 확인

```bash
# 인증서 발급 중에 확인
dig +short TXT _acme-challenge.grafana.your-domain.com
```

---

## 트러블슈팅

### 문제 1: Challenge가 pending 상태로 유지

```bash
kubectl describe challenge <challenge-name> -n <namespace>
```

**가능한 원인:**
1. IAM 권한 부족 (`route53:GetChange` 누락)
2. Public Zone ID 오타
3. Region 설정 오류

### 문제 2: AccessDenied 오류

```
AccessDenied: User is not authorized to perform: route53:GetChange
```

**해결책:**
```bash
# IAM 정책 적용
cd stacks/dev/50-rke2
aws-vault exec devops -- make apply
```

### 문제 3: 인증서 발급 후에도 HTTPS 접속 실패

**확인 사항:**
1. Ingress TLS Secret 이름 확인
2. nginx-ingress 재시작
3. Certificate READY 상태 확인

---

## 체크리스트

- [ ] Route53 Public Zone 생성 완료
- [ ] Route53 Private Zone 생성 완료 (Split-Horizon)
- [ ] RKE2 노드 IAM Role에 Route53 권한 추가
- [ ] cert-manager 설치 완료
- [ ] ClusterIssuer (DNS-01) 생성 완료
- [ ] Ingress에 cert-manager annotation 추가
- [ ] 인증서 발급 확인 (READY: True)

---

## 관련 문서

- [cert-manager 공식 문서 - DNS-01](https://cert-manager.io/docs/configuration/acme/dns01/)
- [AWS Route53 Solver](https://cert-manager.io/docs/configuration/acme/dns01/route53/)
- [HTTP-01 Hairpin Routing 트러블슈팅](./cert-manager-http01-hairpin-issue.md)
