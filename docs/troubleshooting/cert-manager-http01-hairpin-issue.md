# cert-manager HTTP-01 Challenge Hairpin Routing 이슈

> **날짜**: 2026-02-07  
> **상태**: 해결됨 (DNS-01로 전환)  
> **영향 범위**: RKE2 클러스터의 모든 Ingress TLS 인증서

---

## 증상

- ArgoCD, Grafana, Longhorn, Rancher 등 모든 앱에서 TLS 인증서 발급 실패
- Teleport에서 앱 접속 시 `Context Deadline Exceeded` 오류
- cert-manager certificates 상태가 `READY: False`로 유지

```bash
$ kubectl get certificates -A
NAMESPACE         NAME                  READY   SECRET                AGE
cattle-system     tls-rancher-ingress   False   tls-rancher-ingress   28m
longhorn-system   longhorn-tls          False   longhorn-tls          23m
monitoring        grafana-tls           False   grafana-tls           63s
```

---

## 원인 분석

### 1단계: Challenge 상태 확인

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

### 2단계: 문제 원인 파악

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

### 시도 1: VPC DNS 설정 변경 (부분 성공)

```yaml
# cert-manager Helm values
podDnsPolicy: "None"
podDnsConfig:
  nameservers:
    - "10.0.0.2"  # VPC DNS
```

**결과**: DNS 조회는 성공하지만, HTTP 연결에서 여전히 타임아웃

### 시도 2: Self-Check 비활성화 시도 (실패)

```yaml
featureGates: "DisableHTTP01SelfCheck=true"
```

**결과**: cert-manager v1.14+ 에서만 지원, 현재 v1.13.3 사용 중

---

## 최종 해결책: DNS-01 Challenge로 전환

### HTTP-01 vs DNS-01 비교

| 항목 | HTTP-01 | DNS-01 |
|------|---------|--------|
| 검증 방식 | HTTP 엔드포인트 접속 | DNS TXT 레코드 확인 |
| Hairpin 문제 | ❌ 발생 | ✅ 없음 |
| Wildcard 인증서 | ❌ 불가 | ✅ 가능 |
| 필요 권한 | 없음 | Route53 ChangeResourceRecordSets |

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

### 1. ClusterIssuer 수정 (DNS-01 solver 추가)

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@unifiedmeta.net
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - dns01:
          route53:
            region: ap-northeast-2
            # hostedZoneID는 PUBLIC Zone ID
```

### 2. IAM 권한 확인 (글로벌 필수 권한)

EC2 노드의 IAM Role에 다음 권한 필요:

```json
{
  "Effect": "Allow",
  "Action": [
    "route53:GetChange",
    "route53:ChangeResourceRecordSets",
    "route53:ListResourceRecordSets"
  ],
  "Resource": [
    "arn:aws:route53:::hostedzone/PUBLIC_ZONE_ID",
    "arn:aws:route53:::change/*"
  ]
}
```

#### `route53:GetChange` 권한이 필요한 이유

DNS-01 Challenge는 비동기로 작동합니다:

```
┌─────────────────────────────────────────────────────────────────────┐
│                    DNS-01 상세 흐름                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   1️⃣ TXT 레코드 생성 요청                                           │
│       cert-manager → Route53 API (ChangeResourceRecordSets)         │
│       Route53 응답: "Change ID: C0017795xxx" (비동기 작업 시작)      │
│                                                                     │
│   2️⃣ 변경 완료 확인 (GetChange 필수!)                               │
│       cert-manager → Route53 API (GetChange)                        │
│       응답 확인: "PENDING" → "INSYNC"                               │
│                                                                     │
│       • PENDING = DNS 변경이 아직 전파 중                            │
│       • INSYNC = DNS 변경 완료, 검증 가능                            │
│                                                                     │
│   3️⃣ INSYNC 확인 후 Let's Encrypt에 검증 요청                       │
│       cert-manager → ACME 서버: "TXT 레코드 준비 완료"               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**GetChange 없이 발생하는 문제:**
```
AccessDenied: User is not authorized to perform: 
route53:GetChange on resource: arn:aws:route53:::change/C0017795xxx
```

| 권한 | 필수 여부 | 용도 |
|------|----------|------|
| `route53:ChangeResourceRecordSets` | ✅ 필수 | TXT 레코드 생성/삭제 |
| `route53:GetChange` | ✅ **필수** | DNS 변경 완료(INSYNC) 확인 |
| `route53:ListResourceRecordSets` | ⚪ 권장 | 기존 레코드 충돌 방지 |
| `route53:ListHostedZonesByName` | ⚪ 선택 | Zone ID 자동 탐색 |

> **참고**: [cert-manager 공식 문서 - Route53 IAM Policy](https://cert-manager.io/docs/configuration/acme/dns01/route53/)에서 `route53:GetChange`를 필수 권한으로 명시

---

## 교훈

1. **Private 환경에서 HTTP-01은 Hairpin 문제 발생 가능**
2. **DNS-01은 Private 환경에서 더 안정적인 선택**
3. **cert-manager 버전별 feature gate 지원 확인 필요**
4. **Split-Horizon DNS 환경에서는 Public Zone과 Private Zone의 역할 분리 중요**

---

## 관련 문서

- [cert-manager DNS-01 Challenge](https://cert-manager.io/docs/configuration/acme/dns01/)
- [AWS Route53 Solver](https://cert-manager.io/docs/configuration/acme/dns01/route53/)
