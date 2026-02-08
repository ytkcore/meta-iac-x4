# T10: ALBC NLB IP-mode 확인

> **Parent**: [클러스터 안정화](../2026-02-08-cluster-stabilization.md) | **Status**: ✅ 완료 (이미 적용)

## 📋 Summary

AWS Load Balancer Controller(ALBC)가 생성한 NLB의 target type이 `ip` 모드로 정상 동작 중인지 확인. Cilium ENI 모드에서 Pod IP가 VPC CIDR 대역이므로 NLB → Pod 직접 연결이 가능한 상태.

## 🔍 검증 결과

### ALBC 상태
```bash
kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-load-balancer-controller
# NAME                                           READY   STATUS
# aws-load-balancer-controller-xxx-yyy            2/2     Running
# aws-load-balancer-controller-xxx-zzz            2/2     Running
```
✅ 2 replicas Running + Vault Agent Sidecar (2/2)

### TargetGroupBinding 확인
```bash
kubectl get targetgroupbindings -A
```

| Namespace | Name | Target Type |
|-----------|------|-------------|
| ingress-nginx | nginx-ingress-http | `ip` ✅ |
| ingress-nginx | nginx-ingress-https | `ip` ✅ |
| ingress-nginx-internal | nginx-ingress-internal-http | `ip` ✅ |
| ingress-nginx-internal | nginx-ingress-internal-https | `ip` ✅ |

✅ **4개 TGB 모두 `ip` mode**

### Pod IP 검증
```bash
kubectl -n ingress-nginx get pods -o wide
# NAME                        READY   IP
# nginx-ingress-controller-x  1/1     10.0.102.45    # VPC CIDR ✅
# nginx-ingress-controller-y  1/1     10.0.1.112     # VPC CIDR ✅
```

Pod IP가 `10.0.x.x` (VPC CIDR) → NLB가 EC2 Node가 아닌 **Pod에 직접 트래픽 전송** 가능.

## 💡 IP Mode의 장점

### 기존 Instance Mode
```
Client → NLB → EC2 Node (NodePort) → kube-proxy → Pod
```
- NodePort 고갈 위험
- kube-proxy double-hop
- Node 장애 시 target draining 지연

### IP Mode (현재)
```
Client → NLB → Pod (직접)
```
- ✅ NodePort 불필요
- ✅ single-hop (낮은 지연)
- ✅ Pod-level health check
- ✅ ALBC가 자동 target 관리 (스케일링 시 즉시 반영)

> [!NOTE]
> IP mode는 Cilium ENI 모드(VPC-native Pod IP)가 전제. Overlay 네트워크에서는 불가능.

## 📊 아키텍처 흐름

```
Internet → Public NLB  → Pod IP (nginx-ingress)     → Backend Pods
              ↑                   ↑
         ALBC 관리           ALBC 자동 등록
         (TargetGroup)       (TargetGroupBinding)

VPN/SSM → Internal NLB → Pod IP (nginx-internal)     → Backend Pods
```

## 🔧 변경

**변경 없음** — 이미 올바르게 적용된 상태 확인만 수행.

ALBC Helm values에서 이미 설정:
```yaml
# gitops-apps/bootstrap/albc.yaml
aws-load-balancer-controller:
  enableServiceMutatorWebhook: false
  vpcId: "vpc-xxx"
  clusterName: "dev-rke2"
```

nginx-ingress Service annotations:
```yaml
service.beta.kubernetes.io/aws-load-balancer-type: "external"
service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"  # 또는 internal
service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
```

## 🏷️ Labels
`albc`, `nlb`, `ip-mode`, `cilium`, `verification`
