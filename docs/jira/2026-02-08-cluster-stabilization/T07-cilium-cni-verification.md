# T7: Cilium CNI 검증 + 코드 정합성

> **Parent**: [클러스터 안정화](../2026-02-08-cluster-stabilization.md) | **Status**: ✅ 완료

## 📋 Summary

Cilium CNI가 ENI 모드로 정상 동작 중인지 검증하고, Terraform variables.tf의 기본값이 실제 클러스터 설정과 일치하도록 코드 정합성을 확보.

## 🔍 검증 항목

### 1. IPAM 모드 확인
```bash
kubectl -n kube-system exec ds/cilium -- cilium status | grep "IPAM"
# IPAM: eni
```
✅ ENI 모드 = Pod에 VPC ENI의 secondary IP 직접 할당 → overlay 없음

### 2. Pod IP 대역 확인
```bash
kubectl get pods -A -o wide | awk '{print $7}' | sort -u
# 10.0.1.x, 10.0.2.x, 10.0.101.x, 10.0.102.x
```
✅ Pod IP = VPC CIDR 대역 (overlay IP 없음)

### 3. kube-proxy 대체 확인
```bash
kubectl -n kube-system get ds kube-proxy 2>&1
# Error: daemonsets.apps "kube-proxy" not found
```
✅ kube-proxy가 Cilium eBPF로 완전 대체

### 4. Hubble 관측성 확인
```bash
kubectl -n kube-system get pods -l k8s-app=hubble-relay
# hubble-relay-xxx   1/1   Running
kubectl -n kube-system get pods -l k8s-app=hubble-ui
# hubble-ui-xxx      2/2   Running
```
✅ Hubble Relay + UI 정상 동작

### 5. CiliumNetworkPolicy 확인
```bash
kubectl get ciliumnetworkpolicies -A
# keycloak   keycloak-l7-protection   ...
```
✅ L7 정책 정상 적용 (T8의 WAF 역할)

## 🔧 코드 정합성

Terraform variables.tf에서 Cilium 관련 기본값이 실제 설정과 불일치하는 항목 발견 → 수정:

### Before
```hcl
# stacks/dev/50-rke2/variables.tf
variable "cni" {
  default = "canal"     # ❌ 실제: cilium
}
variable "enable_eni_mode" {
  default = false       # ❌ 실제: true
}
variable "disable_ccm" {
  default = true        # 일치 (CCM 비활성)
}
```

### After
```hcl
variable "cni" {
  default = "cilium"    # ✅ 정합
}
variable "enable_eni_mode" {
  default = true        # ✅ 정합
}
variable "disable_ccm" {
  default = false       # ✅ ccm=false (CCM 비활성화)
}
```

## 💡 Cilium ENI 모드의 장점

| 항목 | 기존 (Canal) | 현재 (Cilium ENI) |
|------|-------------|-------------------|
| Pod Network | VXLAN overlay | **VPC-native** |
| Target Group | Node IP + NodePort | **Pod IP 직접** |
| kube-proxy | DaemonSet | **eBPF 대체** |
| Network Policy | Calico L3 | **Cilium L3/L4/L7** |
| 관측성 | 없음 | **Hubble** |

## 🔧 변경 파일

| 파일 | 변경 | 커밋 |
|------|------|------|
| `stacks/dev/50-rke2/variables.tf` | CNI/ENI/CCM defaults 정합 | `0687766` |

## 🏷️ Labels
`cilium`, `cni`, `eni`, `verification`, `code-hygiene`
