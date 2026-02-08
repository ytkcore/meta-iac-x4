# [INFRA] Cilium ENI Mode 전환 + 클러스터 Clean Rebuild (Phase 6)

## 📋 Summary

RKE2 클러스터의 CNI를 **Canal(Flannel+Calico)에서 Cilium ENI Mode로 전환**한다.
Pod IP가 VPC-native가 되어 NLB/ALBC IP-mode가 네이티브로 동작하고,
eBPF 기반 L7 NetworkPolicy, kube-proxy 대체, Hubble 관측성을 확보한다.

기존 Canal의 overlay(10.42.x.x)가 만든 **근본적인 문제 체인**(NLB Target unhealthy, CCM Route 미동작, ALBC IP-mode 불가)을 일괄 해소한다.

## 🎯 Goals

1. **Pod IP = VPC IP**: overlay 제거, NLB/ALB IP-mode 네이티브 동작
2. **eBPF NetworkPolicy**: L3-L7 정책 (HTTP path 수준 제어)
3. **kube-proxy 대체**: eBPF 기반 서비스 라우팅 (O(n) → O(1))
4. **Hubble**: 실시간 네트워크 관측성 (Pod 간 트래픽 플로우)
5. **불필요 컴포넌트 제거**: CCM Route Controller, kube-proxy, Canal

## 📊 전환 전후 비교

| 영역 | Canal (Before) | Cilium (After) |
|------|---------------|----------------|
| Pod IP | 10.42.x.x (overlay) | 10.0.x.x (VPC-native) |
| NLB IP-mode | ❌ unreachable | ✅ 네이티브 |
| CCM 의존성 | Route Controller 필수 | **불필요** |
| NetworkPolicy | L3-L4 (Calico) | L3-L7 (eBPF) |
| kube-proxy | iptables O(n) | eBPF O(1) |
| 관측성 | 없음 | Hubble |

## 📋 Tasks

### Phase 0: 기존 상태 백업

- [ ] **0.1** Vault unseal keys 백업
- [ ] **0.2** Keycloak DB dump (60-postgres)
- [ ] **0.3** ArgoCD app 매니페스트 Git SSOT 확인
- [ ] **0.4** Longhorn volume snapshots → S3 backup 확인
- [ ] **0.5** 기존 NLB/ALB DNS 레코드 기록

### Phase 1: Terraform 코드 수정

- [ ] **1.1** `modules/rke2-cluster` — CNI 설정 변경
  ```hcl
  # cni = "canal" 제거
  cni = "cilium"
  cilium_eni_mode = true
  cilium_enable_prefix_delegation = true  # /28, 240+ pods/node
  cilium_hubble_enabled = true
  cilium_kube_proxy_replacement = "strict"
  ```
- [ ] **1.2** `modules/rke2-cluster/templates/` — server/agent userdata 수정
  - `--disable-kube-proxy` 플래그 추가
  - Canal 관련 설정 제거
- [ ] **1.3** CCM 설정 정리 — Route Controller 관련 제거
- [ ] **1.4** ALBC IAM Policy 확인 (ENI 관련 권한 추가 필요 시)
- [ ] **1.5** Cilium ENI용 IAM 정책 생성
  ```json
  {
    "Effect": "Allow",
    "Action": [
      "ec2:CreateNetworkInterface",
      "ec2:AttachNetworkInterface",
      "ec2:ModifyNetworkInterfaceAttribute",
      "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses"
    ],
    "Resource": "*"
  }
  ```

### Phase 2: 새 클러스터 프로비저닝

- [ ] **2.1** `make init` (50-rke2) — 새 클러스터 구성
- [ ] **2.2** `make apply` (50-rke2) — 프로비저닝
- [ ] **2.3** Cilium 상태 확인
  ```bash
  cilium status
  cilium connectivity test
  ```
- [ ] **2.4** Hubble 활성화 확인
  ```bash
  hubble status
  hubble observe
  ```
- [ ] **2.5** kube-proxy 비활성화 확인
  ```bash
  kubectl get pods -n kube-system | grep kube-proxy  # 없어야 함
  ```

### Phase 3: ArgoCD 부트스트랩

- [ ] **3.1** `make apply` (55-bootstrap)
- [ ] **3.2** ArgoCD 앱 자동 sync 확인
- [ ] **3.3** nginx-ingress Dual NLB 자동 생성 확인
- [ ] **3.4** cert-manager DNS-01 동작 확인
- [ ] **3.5** Keycloak K8s-native 배포 (별도 티켓 참조)

### Phase 4: 데이터 복원 + 검증

- [ ] **4.1** Vault unseal + 기존 데이터 복원
- [ ] **4.2** Keycloak DB import (K8s Pod → 기존 60-postgres 연결)
- [ ] **4.3** NLB Target Health 확인 (IP-mode ✅)
  ```bash
  aws elbv2 describe-target-health --target-group-arn <arn>
  ```
- [ ] **4.4** Hubble 네트워크 flow 검증
- [ ] **4.5** CiliumNetworkPolicy 테스트 (Keycloak Admin/OIDC 경로 분리)

### Phase 5: DNS 전환 + 정리

- [ ] **5.1** Route53 레코드 → 새 NLB/ALB DNS로 업데이트
- [ ] **5.2** 외부 접근 E2E 테스트
- [ ] **5.3** Teleport App Access 동작 확인
- [ ] **5.4** 기존 클러스터 자원 정리
- [ ] **5.5** 문서 업데이트

## ⚠️ Risk & Notes

| 리스크 | 확률 | 영향 | 대응 |
|--------|------|------|------|
| VPC CIDR 소진 | 낮음 | 높음 | 서브넷 CIDR 용량 사전 계산 |
| Pod 밀도 제한 (t3.large: 24 pods) | 중간 | 중간 | Prefix Delegation `/28` 활성화 (240+ pods) |
| 재구축 다운타임 | 확정 | 중간 | Blue-Green + DNS 전환 |
| EC2 ENI API Rate Limit | 낮음 | 낮음 | Warm pool 설정 |
| Cilium 학습 곡선 | 중간 | 낮음 | Hubble UI + 공식 문서 |

## 🔗 Dependencies

- `50-rke2`: 클러스터 모듈 수정
- `55-bootstrap`: ArgoCD 앱 재배포
- `60-postgres`: Keycloak DB
- `15-access-control`: Teleport 재설정

## ⏸️ 이 티켓이 해소하는 기존 이슈

| 기존 티켓 | 해소 방식 |
|----------|----------|
| Phase 1 (ALBC + NLB IP mode) | Cilium ENI로 Pod IP가 VPC-native → IP-mode 네이티브 동작 |
| Phase 3 (IAM OIDC) | 클러스터 재구축 시 OIDC Provider 설정 포함 |
| Phase 5 (CCM 제거) | Cilium이 CCM Route Controller 대체 |
| NLB Target 수동 등록 | ALBC IP mode 자동 관리 |

## 📎 References

- [17-cilium-cni-architecture.md](../architecture/17-cilium-cni-architecture.md) — Cilium 전환 상세 아키텍처
- [16-architecture-evolution-decision.md](../architecture/16-architecture-evolution-decision.md) — 최종 의사결정
- [Cilium 공식 문서](https://docs.cilium.io/)
- [Cilium ENI IPAM](https://docs.cilium.io/en/stable/network/concepts/ipam/eni/)

## 🏷️ Labels

`cilium`, `cni`, `rebuild`, `phase-6`, `critical`

## 📌 Priority

**Critical** — 모든 네트워크 문제의 근본 해결

## 📅 예상 기간

**D14-16** (3일)
