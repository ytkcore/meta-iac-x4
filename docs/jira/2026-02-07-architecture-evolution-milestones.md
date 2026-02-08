# [INFRA] 아키텍처 고도화 — 마일스톤별 구현 티켓

> **최종 업데이트**: 2026-02-08  
> **근거 문서**: [16-architecture-evolution-decision.md](../architecture/16-architecture-evolution-decision.md), [17-cilium-cni-architecture.md](../architecture/17-cilium-cni-architecture.md)

---

## Phase 1: ALBC + NLB IP Mode (D1-2) ⏸️ → Phase 6에서 해소

> **상태 변경**: ✅ → ⏸️  
> **사유**: Canal overlay(10.42.x.x)에서는 NLB IP-mode가 근본적으로 불가. Cilium ENI Mode 전환(Phase 6)으로 자연 해소.

### Summary
AWS Load Balancer Controller를 도입하여 CCM의 NLB Target 수동 등록 문제를 근본 해결한다.
nginx-ingress NLB를 Instance mode에서 IP mode로 전환한다.

### Scope

| 파일 | 작업 |
|------|------|
| `modules/albc-iam/` | 🆕 IAM Policy 모듈 생성 |
| `stacks/dev/50-rke2/main.tf` | ✏️ albc_iam 모듈 호출 추가 |
| `gitops-apps/bootstrap/aws-load-balancer-controller.yaml` | 🆕 ArgoCD App |
| `gitops-apps/bootstrap/nginx-ingress.yaml` | ✏️ IP mode annotations |
| `gitops-apps/bootstrap/nginx-ingress-internal.yaml` | ✏️ IP mode annotations |

### Labels
`albc`, `nlb`, `phase-1`

---

## Phase 2: Keycloak SSO (D3-7) ✅ 설계 완료

### Summary
Keycloak IdP를 EC2(Docker Compose)로 배포하고, 5개 서비스(Grafana, ArgoCD, Rancher, Harbor, Teleport)에 OIDC SSO를 연동한다.

> **Note**: Phase 6(Cilium 재구축) 시점에 Keycloak을 K8s-native로 전환 예정.  
> 상세: [2026-02-08-keycloak-k8s-migration.md](2026-02-08-keycloak-k8s-migration.md)

### Scope

| 파일 | 작업 |
|------|------|
| `modules/keycloak-ec2/` | 🆕 Keycloak EC2 모듈 생성 (4파일) |
| `stacks/dev/25-keycloak/` | 🆕 Keycloak 스택 생성 (5파일) |
| `gitops-apps/bootstrap/monitoring.yaml` | ✏️ Grafana OIDC 연동 |
| ArgoCD values template | ✏️ OIDC config 추가 |
| `gitops-apps/bootstrap/rancher.yaml` | ✏️ Keycloak 연동 |
| Harbor OIDC 설정 | ✏️ auth_mode: oidc_auth |
| Teleport OIDC Connector | ✏️ Keycloak OIDC 추가 |

### Acceptance Criteria
- [ ] Keycloak 웹 UI 접근 가능 (SSM 터널 경유)
- [ ] Grafana 로그인 시 Keycloak SSO 리다이렉트
- [ ] ArgoCD 로그인 시 Keycloak SSO 리다이렉트
- [ ] 단일 계정으로 모든 서비스 접근

### Labels
`keycloak`, `sso`, `oidc`, `phase-2`

---

## Phase 3: Keycloak → AWS IAM OIDC Federation (D8-9) ⏸️ → Phase 6 이후

> **상태 변경**: 미착수 → ⏸️  
> **사유**: Cilium 클러스터 재구축 시 OIDC Provider 설정을 포함하여 자연 해소.

### Summary
Keycloak을 AWS IAM OIDC Provider로 등록하여, Pod별 IAM Role(IRSA) 분리를 실현한다.
Node IAM Role에서 ALBC 정책을 분리하고, Pod-level 인증으로 전환한다.

### Scope

| 파일 | 작업 |
|------|------|
| `stacks/dev/25-keycloak/main.tf` | ✏️ aws_iam_openid_connect_provider 추가 |
| `stacks/dev/50-rke2/main.tf` | ✏️ ALBC 전용 IRSA Role 생성 |
| `gitops-apps/bootstrap/aws-load-balancer-controller.yaml` | ✏️ ServiceAccount IRSA annotation |

### Acceptance Criteria
- [ ] Keycloak JWT로 AWS STS AssumeRoleWithWebIdentity 성공
- [ ] ALBC Pod이 IRSA Role로 NLB 관리
- [ ] Node IAM Role에서 ALBC 정책 분리 완료

### Labels
`oidc`, `iam`, `irsa`, `phase-3`

---

## Phase 4: Vault 배포 + Dynamic Secrets (D10-12) ✅ 설계 완료

### Summary
HashiCorp Vault를 K8s 내에 배포하고, Keycloak Auth + PostgreSQL Dynamic Secrets를 구성한다.
K8s Secret(평문) → Vault(동적 시크릿 + 자동 회전)로 전환한다.

### Scope

| 파일 | 작업 |
|------|------|
| `gitops-apps/bootstrap/vault.yaml` | 🆕 Vault ArgoCD App |
| Vault Keycloak Auth 설정 | 🆕 OIDC Auth backend |
| PostgreSQL dynamic secrets engine | 🆕 임시 DB 계정 자동 발급 |
| K8s Auth method | 🆕 Pod → Vault 인증 |

### Acceptance Criteria
- [ ] Vault UI 접근 가능 (Keycloak SSO)
- [ ] `vault read database/creds/readonly` → 임시 DB 계정 발급
- [ ] 발급된 계정 자동 만료 확인
- [ ] Vault Audit Log에 접근 기록 확인

### Labels
`vault`, `secrets`, `dynamic-secrets`, `phase-4`

---

## Phase 5: CCM 제거 + 통합 테스트 (D13) ⏸️ → Phase 6에서 해소

> **상태 변경**: 미착수 → ⏸️  
> **사유**: Cilium ENI Mode가 CCM Route Controller를 대체. 클러스터 재구축 시 CCM 자체가 불필요.

### Summary
AWS Cloud Controller Manager를 제거하고 ALBC로 완전 전환한다.
기존 NLB를 Terraform import로 보존하고, 전체 서비스 E2E 테스트를 수행한다.

### Scope

| 파일 | 작업 |
|------|------|
| `gitops-apps/bootstrap/aws-cloud-controller-manager.yaml` | 🗑️ 삭제 |
| `stacks/dev/50-rke2` | ✏️ CCM cloud-provider 설정 정리 |
| NLB Terraform import | ✏️ 기존 NLB 보존 |

### Acceptance Criteria
- [ ] CCM Pod 제거 확인 (`kubectl get pods -n kube-system`)
- [ ] NLB IP 변경 없음 확인
- [ ] 모든 서비스 E2E 접근 테스트 통과
- [ ] 문서 업데이트 완료

### Labels
`ccm`, `cleanup`, `integration-test`, `phase-5`

---

## Phase 6: Cilium CNI + 클러스터 재구축 + Keycloak K8s (D14-16) 🆕 최우선

> **신규 추가**: 2026-02-08  
> **이 Phase가 해소하는 것**: Phase 1 (ALBC IP-mode), Phase 3 (IAM OIDC), Phase 5 (CCM 제거)

### Summary
RKE2 CNI를 Canal → Cilium ENI Mode로 전환하는 **Clean Rebuild**를 수행한다.
동시에 Keycloak을 EC2에서 K8s-native로 마이그레이션한다.

Pod IP가 VPC-native가 되어 모든 네트워크 문제가 근본 해소되고,
eBPF 기반 L7 NetworkPolicy, kube-proxy 대체, Hubble 관측성을 확보한다.

### Scope

| 작업 | 상세 | 상세 티켓 |
|------|------|----------|
| Cilium ENI Mode 전환 | CNI 교체 + Clean Rebuild | [2026-02-08-cilium-cni-migration.md](2026-02-08-cilium-cni-migration.md) |
| Keycloak K8s 마이그레이션 | EC2 → K8s-native + Dual Ingress | [2026-02-08-keycloak-k8s-migration.md](2026-02-08-keycloak-k8s-migration.md) |
| CCM 제거 | Cilium이 대체 → 자연 해소 | Phase 5 흡수 |
| ALBC IP-mode | VPC-native Pod IP → 네이티브 동작 | Phase 1 흡수 |
| IAM OIDC | 재구축 시 포함 | Phase 3 흡수 |

### Acceptance Criteria
- [ ] Cilium status 정상 + connectivity test 통과
- [ ] NLB Target Health = healthy (IP-mode)
- [ ] kube-proxy Pod 없음 (`kubectl get pods -n kube-system`)
- [ ] Hubble 네트워크 flow 관측 가능
- [ ] CiliumNetworkPolicy L7 동작 확인
- [ ] Keycloak K8s-native SSO 동작 확인
- [ ] 모든 서비스 E2E 접근 테스트 통과

### Labels
`cilium`, `cni`, `rebuild`, `keycloak`, `phase-6`, `critical`
