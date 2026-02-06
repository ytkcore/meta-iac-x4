# cert-manager HTTP-01 Challenge Hairpin Routing 이슈

> **날짜**: 2026-02-07  
> **상태**: 해결됨 (DNS-01로 전환)  
> **영향 범위**: RKE2 클러스터의 모든 Ingress TLS 인증서

---

## 목차

1. [증상](#증상)
2. [원인 분석](#원인-분석)
3. [시도한 해결책들](#시도한-해결책들)
4. [최종 해결책: DNS-01 Challenge](#최종-해결책-dns-01-challenge로-전환)
5. [구현 단계](#구현-단계)
6. [교훈](#교훈)

---

## 증상

### 관찰된 문제

- ArgoCD, Grafana, Longhorn, Rancher 등 모든 앱에서 TLS 인증서 발급 실패
- Teleport에서 앱 접속 시 **`Context Deadline Exceeded`** 오류
- cert-manager certificates 상태가 `READY: False`로 유지

### 확인 방법

```bash
$ kubectl get certificates -A
NAMESPACE         NAME                  READY   SECRET                AGE
cattle-system     tls-rancher-ingress   False   tls-rancher-ingress   28m
longhorn-system   longhorn-tls          False   longhorn-tls          23m
monitoring        grafana-tls           False   grafana-tls           63s
```

---

## 원인 분석

### Challenge 상태 확인

```bash
$ kubectl describe challenge -n monitoring grafana-tls-1-xxx
```

**오류 메시지:**
```
Reason: Waiting for HTTP-01 challenge propagation: 
failed to perform self check GET request 
'http://grafana.unifiedmeta.net/.well-known/acme-challenge/xxx': 
Get "...": dial tcp 3.39.213.129:80: i/o timeout
```

### 문제 원인: Hairpin Routing

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Hairpin Routing 문제                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   cert-manager Pod (VPC 내부)                                       │
│         │                                                           │
│         │ 1️⃣ DNS 조회: grafana.unifiedmeta.net                      │
│         ▼                                                           │
│   Route53 Private Zone                                              │
│         │                                                           │
│         │ 2️⃣ 응답: NLB Public IP (3.39.213.129)                     │
│         ▼                                                           │
│   cert-manager Pod                                                  │
│         │                                                           │
│         │ 3️⃣ HTTP GET: http://3.39.213.129/.well-known/...          │
│         ▼                                                           │
│   ❌ TIMEOUT (VPC 내부 → Public IP → Hairpin 불가)                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Hairpin Routing이란?**
- VPC 내부에서 Public IP로 나갔다가 다시 VPC 내부로 들어오는 트래픽
- AWS NLB는 기본적으로 이를 지원하지 않음
- 결과: 타임아웃 발생

---

## 시도한 해결책들

### 시도 1: VPC DNS 설정 변경

```yaml
# cert-manager Helm values
podDnsPolicy: "None"
podDnsConfig:
  nameservers:
    - "10.0.0.2"  # VPC DNS
```

**결과**: ❌ DNS 조회는 성공하지만, HTTP 연결에서 여전히 타임아웃

### 시도 2: Self-Check 비활성화

```yaml
featureGates: "DisableHTTP01SelfCheck=true"
```

**결과**: ❌ cert-manager v1.14+ 에서만 지원 (현재 v1.13.3 사용 중)

---

## 최종 해결책: DNS-01 Challenge로 전환

### HTTP-01 vs DNS-01 비교

| 항목 | HTTP-01 | DNS-01 |
|------|---------|--------|
| 검증 방식 | HTTP 엔드포인트 접속 | DNS TXT 레코드 확인 |
| Hairpin 문제 | ❌ 발생 | ✅ 없음 |
| Wildcard 인증서 | ❌ 불가 | ✅ 가능 |
| Private 환경 호환성 | ❌ 문제 있음 | ✅ 완벽 호환 |
| 필요 권한 | 없음 | Route53 IAM 권한 |

### DNS-01 작동 원리

```
┌─────────────────────────────────────────────────────────────────────┐
│                    DNS-01 Challenge 흐름                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   1️⃣ cert-manager → Route53 PUBLIC Zone                             │
│      "_acme-challenge.grafana.unifiedmeta.net" TXT 레코드 생성      │
│                                                                     │
│   2️⃣ Let's Encrypt → Public DNS                                     │
│      TXT 레코드 확인 (HTTP 접속 불필요)                              │
│                                                                     │
│   3️⃣ 검증 성공 → 인증서 발급                                         │
│                                                                     │
│   ✅ Hairpin 문제 완전 회피                                          │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 구현 단계

### 1. ClusterIssuer 수정 (DNS-01 solver)

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: devops@unifiedmeta.net
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - dns01:
          route53:
            region: ap-northeast-2
            hostedZoneID: Z09535251FN1BQ4E3N9ID  # PUBLIC Zone ID
```

### 2. IAM 권한 설정 (글로벌 필수)

EC2 노드의 IAM Role에 다음 권한 필요:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["route53:ChangeResourceRecordSets"],
      "Resource": "arn:aws:route53:::hostedzone/PUBLIC_ZONE_ID"
    },
    {
      "Effect": "Allow",
      "Action": ["route53:GetChange"],
      "Resource": "arn:aws:route53:::change/*"
    },
    {
      "Effect": "Allow",
      "Action": ["route53:ListHostedZones", "route53:ListResourceRecordSets"],
      "Resource": "*"
    }
  ]
}
```

#### `route53:GetChange` 권한이 필요한 이유

```
┌─────────────────────────────────────────────────────────────────────┐
│                    DNS-01 비동기 흐름                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   1️⃣ TXT 레코드 생성 요청                                           │
│       cert-manager → Route53 (ChangeResourceRecordSets)             │
│       응답: "Change ID: C0017795xxx" (비동기 작업)                   │
│                                                                     │
│   2️⃣ 변경 완료 확인 (GetChange 필수!)                               │
│       cert-manager → Route53 (GetChange)                            │
│       폴링: "PENDING" → "INSYNC"                                    │
│                                                                     │
│       • PENDING = DNS 변경 전파 중                                   │
│       • INSYNC = DNS 변경 완료, 검증 가능                            │
│                                                                     │
│   3️⃣ INSYNC 확인 후 Let's Encrypt에 검증 요청                       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**GetChange 없이 발생하는 에러:**
```
AccessDenied: User is not authorized to perform: 
route53:GetChange on resource: arn:aws:route53:::change/C0017795xxx
```

| 권한 | 필수 여부 | 용도 |
|------|----------|------|
| `route53:ChangeResourceRecordSets` | ✅ 필수 | TXT 레코드 생성/삭제 |
| `route53:GetChange` | ✅ **필수** | DNS 전파 완료 확인 |
| `route53:ListResourceRecordSets` | ⚪ 권장 | 기존 레코드 충돌 방지 |
| `route53:ListHostedZonesByName` | ⚪ 선택 | Zone ID 자동 탐색 |

### 3. 인증서 재생성

```bash
# 기존 인증서 삭제 (Ingress가 자동 재생성)
kubectl delete certificates -A --all
kubectl delete challenges.acme.cert-manager.io -A --all
kubectl delete orders.acme.cert-manager.io -A --all

# 새 인증서 발급 상태 확인
kubectl get certificates -A --watch
```

---

## 교훈

1. **Private 환경에서 HTTP-01은 Hairpin 문제 발생 가능** → DNS-01 필수
2. **DNS-01은 Private 환경에서 더 안정적인 선택**
3. **cert-manager 버전별 feature gate 지원 확인 필요** (v1.14+)
4. **Split-Horizon DNS 환경에서는 Public Zone과 Private Zone의 역할 분리 중요**
5. **`route53:GetChange`는 DNS-01에서 필수 권한** (cert-manager 공식 문서 명시)

---

## 관련 문서

- [cert-manager DNS-01 Challenge](https://cert-manager.io/docs/configuration/acme/dns01/)
- [AWS Route53 Solver - IAM Policy](https://cert-manager.io/docs/configuration/acme/dns01/route53/)
- [Private VPC RKE2 TLS 설정 가이드](./rke2-private-vpc-tls-setup-guide.md)
