# 웹서비스 온보딩 가이드

**작성일**: 2026-02-07  
**환경**: dev-meta RKE2 클러스터  
**관련 문서**: [NLB 아키텍처](../architecture/nlb-architecture.md), [DNS 전략](../architecture/dns-strategy.md)

---

## 1. 개요

RKE2 클러스터에 새로운 서비스를 배포하고 외부/내부에서 접근 가능하게 만드는 표준 절차.

### 서비스 유형별 경로

| 유형 | 접근 경로 | NLB | Teleport 등록 |
|------|---------|-----|-------------|
| **고객 대상 웹서비스** | 외부 사용자 → Public NLB | Public | 불필요 |
| **내부 관리 UI** | 관리자 → Teleport → Internal NLB | Internal | **필요** |
| **양쪽 접근 필요** | 위 두 경로 모두 | 양쪽 | 필요 |

---

## 2. 고객 대상 웹서비스 추가 절차

### Step 1: Pod + Service 배포 (GitOps)

```yaml
# gitops-apps/apps/<service-name>.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-web-service
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://harbor.unifiedmeta.net/chartrepo/library
    chart: my-web-service
    targetRevision: "1.0.0"
  destination:
    server: https://kubernetes.default.svc
    namespace: my-web-service
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Step 2: Ingress 생성

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-web-service
  namespace: my-web-service
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-dns01  # DNS-01 TLS (hairpin 방지)
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - myapp.unifiedmeta.net
      secretName: myapp-tls
  rules:
    - host: myapp.unifiedmeta.net
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-web-service
                port:
                  number: 80
```

> **주의**: `cert-manager.io/cluster-issuer`는 반드시 `letsencrypt-dns01`을 사용.  
> HTTP-01 challenge는 hairpin routing 문제로 실패함 ([참고](../troubleshooting/cert-manager-http01-hairpin-issue.md)).

### Step 3: Public NLB Target 등록

> ⚠️ **CCM bug 환경 (현재)**에서만 필요. ALBC 도입 후에는 자동.

```bash
# 1. Public nginx-ingress NodePort 확인
kubectl get svc nginx-ingress-ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{range .spec.ports[*]}{.name}:{.nodePort} {end}'
# 출력 예: http:31423 https:32368

# 2. Target Group ARN 확인 (AWS Console 또는 CLI)
aws elbv2 describe-target-groups \
  --load-balancer-arn <PUBLIC_NLB_ARN> \
  --query "TargetGroups[*].[TargetGroupArn,Port]" --output table

# 3. Worker Node를 TG에 등록
aws elbv2 register-targets --target-group-arn <HTTPS_TG_ARN> \
  --targets Id=i-xxx,Port=32368 Id=i-yyy,Port=32368 ...
aws elbv2 register-targets --target-group-arn <HTTP_TG_ARN> \
  --targets Id=i-xxx,Port=31423 Id=i-yyy,Port=31423 ...

# 4. Target Health 확인
aws elbv2 describe-target-health --target-group-arn <HTTPS_TG_ARN> \
  --query "TargetHealthDescriptions[].[Target.Id,TargetHealth.State]" --output table
```

### Step 4: DNS 확인

external-dns가 Public Zone에 자동 등록. 확인:

```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id <PUBLIC_ZONE_ID> \
  --query "ResourceRecordSets[?Name=='myapp.unifiedmeta.net.']" --output table
```

### Step 5: 검증

```bash
# 외부 접근 테스트
curl -k https://myapp.unifiedmeta.net

# TLS 인증서 확인
echo | openssl s_client -connect myapp.unifiedmeta.net:443 -servername myapp.unifiedmeta.net 2>/dev/null | openssl x509 -noout -subject -dates
```

---

## 3. 내부 관리 UI 추가 절차

### Step 1-2: Pod + Ingress (위와 동일)

### Step 3: Internal NLB Target 확인

Internal NLB Target은 이미 등록되어 있으므로 (기존 Worker 4대), 추가 작업 불필요.
단, Worker Node가 변경된 경우 수동 등록 필요.

### Step 4: Private Zone DNS 설정

Ingress에 annotation 추가:

```bash
kubectl annotate ingress my-admin-ui -n <namespace> \
  external-dns.alpha.kubernetes.io/target=<INTERNAL_NLB_DNS> --overwrite
```

### Step 5: Teleport 앱 등록

```bash
# Teleport EC2에서 실행 (SSM 경유)
cat <<EOF | tctl create -f
kind: app
version: v3
metadata:
  name: my-admin-ui
  labels:
    env: dev
    teleport.dev/origin: dynamic
spec:
  uri: https://my-admin-ui.unifiedmeta.net
  insecure_skip_verify: true
EOF
```

### Step 6: `80-access-gateway` 영구 등록

`stacks/dev/80-access-gateway/variables.tf`에 추가:

```hcl
variable "kubernetes_services" {
  default = [
    # ... 기존 서비스 ...
    {
      name     = "my-admin-ui"
      uri      = "https://my-admin-ui.unifiedmeta.net"
      type     = "web"
      internal = true
    }
  ]
}
```

---

## 4. 체크리스트 요약

### 고객 대상 웹서비스

- [ ] ArgoCD Application 생성
- [ ] Ingress (cert-manager DNS-01) 생성
- [ ] Public NLB TG에 Worker 등록 (CCM bug 환경)
- [ ] Public DNS 자동 등록 확인
- [ ] 외부 접근 + TLS 검증

### 내부 관리 UI

- [ ] ArgoCD Application 생성
- [ ] Ingress (cert-manager DNS-01) 생성
- [ ] Ingress annotation `external-dns.alpha.kubernetes.io/target` 추가
- [ ] Private Zone DNS 확인
- [ ] Teleport tctl 앱 등록
- [ ] `80-access-gateway/variables.tf` 업데이트
- [ ] Teleport Web UI에서 접근 테스트

---

## 5. ALBC 도입 후 변경

ALBC 도입 후에는 **Step 3 (NLB Target 수동 등록)이 완전히 제거**됩니다:

| 절차 | CCM 환경 (현재) | ALBC 환경 (미래) |
|------|---------------|-----------------|
| Pod/Service 배포 | 동일 | 동일 |
| Ingress 생성 | 동일 | 동일 |
| NLB Target 등록 | **수동** ⚠️ | **자동** ✅ |
| DNS 등록 | external-dns 자동 | 동일 |
| Teleport 등록 | 수동 tctl | 동일 |

Jira 티켓: [ALBC 도입](../jira/albc-adoption.md)
