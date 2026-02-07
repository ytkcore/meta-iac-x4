# [INFRA] AWS Load Balancer Controller 도입 — IP Mode Target 자동 관리

## 📋 Summary

현재 AWS CCM(Cloud Controller Manager)이 NLB Target Group에 Worker Node를 자동 등록하지 못하는 버그로 인해 수동 운영이 필요한 상태.
AWS Load Balancer Controller(ALBC)를 도입하여 CCM의 LoadBalancer 기능을 대체하고, IP mode 기반 Target 자동 관리를 구현한다.

## 🎯 Goals

1. NLB Target Group 수동 등록 제거 → **Pod IP 자동 등록**
2. Instance mode → **IP mode** 전환 (2-hop → 1-hop, 성능 향상)
3. Worker Node 추가/제거 시 수동 TG 업데이트 필요 없음
4. NodePort 의존 제거 → SG 규칙 간소화

## 📊 현재 상태 vs 목표

| 항목 | AS-IS (CCM) | TO-BE (ALBC) |
|------|-------------|-------------|
| Target Type | Instance (Worker:NodePort) | **IP (Pod 직접)** |
| 경로 | NLB → Worker → kube-proxy → Pod | NLB → **Pod 직접** |
| Target 등록 | 수동 ⚠️ | **자동** |
| Pod 스케일 | TG 변화 없음 | **자동 증감** |
| Worker 추가 | 수동 TG 업데이트 | **자동** |
| NodePort | 필요 (32081, 32419) | 불필요 |

## 📋 Tasks

### Phase 1: 사전 준비

- [ ] **1.1** IAM OIDC Provider 설정 (RKE2 수동 구성)
- [ ] **1.2** ALBC용 IAM Policy 생성 (`AWSLoadBalancerControllerIAMPolicy`)
- [ ] **1.3** ALBC용 IAM Role 생성 (ServiceAccount annotation)
- [ ] **1.4** VPC Subnet 태그 확인
  ```
  kubernetes.io/role/internal-elb: 1  (private subnet)
  kubernetes.io/role/elb: 1          (public subnet)
  ```

### Phase 2: ALBC 설치

- [ ] **2.1** ArgoCD Application 생성 (`gitops-apps/bootstrap/aws-load-balancer-controller.yaml`)
- [ ] **2.2** Helm values 설정 (clusterName, region, vpcId, serviceAccount)
- [ ] **2.3** ALBC Pod 정상 동작 확인

### Phase 3: Internal NLB 전환

- [ ] **3.1** `nginx-ingress-internal.yaml` annotation 변경
  ```diff
  - service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
  - service.beta.kubernetes.io/aws-load-balancer-internal: "true"
  + service.beta.kubernetes.io/aws-load-balancer-type: "external"
  + service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
  + service.beta.kubernetes.io/aws-load-balancer-scheme: "internal"
  ```
- [ ] **3.2** 새 Internal NLB 생성 확인 + TG 자동 등록 검증
- [ ] **3.3** Private Zone DNS 업데이트 (새 NLB DNS)
- [ ] **3.4** Teleport EC2 → 서비스 curl 200 확인

### Phase 4: Public NLB 전환 (웹서비스 배포 시)

- [ ] **4.1** `nginx-ingress.yaml` annotation 변경 (IP mode)
- [ ] **4.2** Public NLB TG 자동 등록 확인
- [ ] **4.3** 외부 사용자 접근 테스트

### Phase 5: 정리

- [ ] **5.1** 수동 Target 등록 제거
- [ ] **5.2** 불필요한 NodePort SG 규칙 제거
- [ ] **5.3** 문서 업데이트 (`docs/architecture/nlb-architecture.md`)

## ⚠️ Risk & Notes

- ALBC 도입 시 NLB 재생성 필요 → **DNS 변경 + 일시 다운타임**
- CCM은 유지 (Node/Route 관리), LoadBalancer 기능만 ALBC가 대체
- RKE2에서 OIDC Provider 수동 구성이 복잡할 수 있음
- 별도 유지보수 윈도우에서 진행 권장

## 🔗 Dependencies

- `55-bootstrap`: nginx-ingress Helm charts
- `15-access-control`: Teleport 서버 (DNS 변경 후 re-config)
- IAM: 신규 Role/Policy 생성 필요

## 📎 References

- [AWS Load Balancer Controller 공식 문서](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [NLB IP mode 설정 가이드](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/service/nlb/)
- [docs/architecture/nlb-architecture.md](../architecture/nlb-architecture.md)
