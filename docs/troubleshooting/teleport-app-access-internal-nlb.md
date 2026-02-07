# Teleport App Access 트러블슈팅: Internal NLB + Private Zone DNS

> **작성일**: 2026-02-07
> **환경**: dev-meta RKE2 클러스터, AWS ap-northeast-2
> **결과**: 해결 ✅

## 증상

Teleport Web UI에서 K8s 서비스(Grafana, Longhorn, Rancher, ArgoCD)에 접속 시 "context deadline exceeded" 에러 발생. Harbor만 정상 접근 가능.

## 근본 원인 (3가지)

### 1. AWS CCM이 NLB Target을 등록하지 않음

RKE2의 AWS Cloud Controller Manager가 NLB를 생성하지만 **Target Group에 Worker Node를 등록하지 않는** 버그가 있음. Public NLB, Internal NLB 모두 동일 증상.

```
# 확인 방법
aws elbv2 describe-target-health --target-group-arn <TG_ARN>
# 결과: TargetHealthDescriptions: [] (빈 배열)
```

**원인 추정**: In-tree cloud provider와 External CCM 간 conflict. CCM은 Leader Election 성공, NLB 생성 완료, 그러나 Target 등록 로직 미동작.

### 2. Private Zone DNS가 Internal NLB를 가리키지 않음

external-dns-private가 Ingress의 ADDRESS(Public NLB DNS)를 기반으로 Private Zone 레코드를 생성. Teleport EC2에서 PUBLIC NLB IP로 resolve → VPC 내부에서 해당 IP에 도달하지 못해 connection refused.

### 3. Teleport 앱 미등록

`80-access-gateway` stack의 `make apply`가 실행되지 않아 K8s 서비스(argocd, grafana, longhorn, rancher)가 Teleport에 등록되지 않음.

## 해결 방법

### Step 1: Helm 기반 Internal nginx-ingress 배포

```yaml
# gitops-apps/bootstrap/nginx-ingress-internal.yaml
# CCM이 자동으로 NLB를 생성하되, Target은 수동 등록
controller:
  ingressClassResource:
    name: nginx
    enabled: false  # 기존 controller의 IngressClass 공유
  ingressClass: nginx
  electionID: ingress-controller-leader-internal  # 별도 leader election
  service:
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
      service.beta.kubernetes.io/aws-load-balancer-internal: "true"
```

### Step 2: Worker Node를 Target Group에 수동 등록

```bash
# NodePort 확인
kubectl get svc nginx-ingress-internal-ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{range .spec.ports[*]}{.name}:{.nodePort} {end}'
# http:32419 https:32081

# Worker Instance IDs 확인
aws ec2 describe-instances --filters "Name=tag:Name,Values=*worker*" \
  --query "Reservations[*].Instances[*].[InstanceId,PrivateIpAddress]" --output table

# Target 등록 (HTTPS TG)
aws elbv2 register-targets --target-group-arn <TG_ARN> \
  --targets Id=i-xxx,Port=32081 Id=i-yyy,Port=32081 ...

# Target 등록 (HTTP TG)
aws elbv2 register-targets --target-group-arn <TG_ARN> \
  --targets Id=i-xxx,Port=32419 Id=i-yyy,Port=32419 ...
```

### Step 3: Private Zone DNS 업데이트

```bash
# Ingress에 annotation 추가 (external-dns가 읽어서 DNS 업데이트)
kubectl annotate ingress <INGRESS_NAME> -n <NAMESPACE> \
  external-dns.alpha.kubernetes.io/target=<INTERNAL_NLB_DNS> --overwrite

# Route53 수동 업데이트 (EvaluateTargetHealth=false 중요!)
aws route53 change-resource-record-sets --hosted-zone-id <ZONE_ID> \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "<service>.unifiedmeta.net",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "<NLB_HOSTED_ZONE>",
          "DNSName": "<INTERNAL_NLB_DNS>",
          "EvaluateTargetHealth": false
        }
      }
    }]
  }'
```

> **주의**: `EvaluateTargetHealth: true`로 설정하면, Target이 일시적으로 unhealthy할 때 DNS가 아예 응답하지 않음.

### Step 4: Teleport 앱 등록

```bash
# SSM을 통해 Teleport EC2에서 실행
for app in argocd grafana longhorn rancher; do
  cat <<EOF | tctl create -f
kind: app
version: v3
metadata:
  name: $app
  labels:
    env: dev
    teleport.dev/origin: dynamic
spec:
  uri: https://$app.unifiedmeta.net
  insecure_skip_verify: true
EOF
done
```

## 검증 결과

```
=== Teleport EC2 → 서비스 연결 ===
grafana  → 10.0.2.54   → HTTP 200 ✅
longhorn → 10.0.2.54   → HTTP 200 ✅
rancher  → 10.0.21.111 → HTTP 200 ✅
argocd   → 10.0.2.54   → HTTP 200 ✅
harbor   → 10.0.202.214 → HTTP 200 ✅

=== Teleport 앱 목록 ===
argocd, grafana, harbor, longhorn, rancher (5개)
```

## ⚠️ 알려진 제약사항

1. **Worker Node 추가/제거 시** Internal NLB Target Group 수동 업데이트 필요
2. **CCM Target 자동 등록 미작동** — 추후 AWS Load Balancer Controller 도입으로 해결 가능
3. **external-dns가 DNS를 덮어쓸 수 있음** — Ingress annotation 유지 필수
4. **Public NLB TG는 현재 비어있어도 정상** — 고객 대상 웹서비스 없음. 향후 배포 시 등록
