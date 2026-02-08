# [INFRA] 클러스터 안정화 — CCM 정리 + Monitoring Synced + Internal 전환 + Vault 검토 + WAF + Auto-Unseal + SSO

## 📋 Summary

클러스터 감사 결과 발견된 안정화 항목 11건을 처리. **13/13 ArgoCD 앱 Synced + Healthy** 달성.
CCM 정리, Monitoring 5-blocker, Ingress Internal, Keycloak Split-Horizon + WAF, Cilium CNI 검증, Vault HA + KMS Auto-Unseal, IMDS hop_limit, ALBC IP-mode 확인, Keycloak SSO Grafana 연동.

커밋: `ffda789` → … → `0687766` → `7221364` → `94d787c` → `ffb5877` → `bf18e79` → `0745cc8`

### 📎 Sub-tickets (상세 워크스루)

> 디렉토리: [`2026-02-08-cluster-stabilization/`](./2026-02-08-cluster-stabilization/)

| # | 제목 | 파일 |
|---|------|------|
| T1 | CCM CrashLoopBackOff 정리 | [T01-ccm-crashloop-cleanup.md](./2026-02-08-cluster-stabilization/T01-ccm-crashloop-cleanup.md) |
| T2 | Monitoring 5-Blocker 해결 | [T02-monitoring-outofsync-resolution.md](./2026-02-08-cluster-stabilization/T02-monitoring-outofsync-resolution.md) |
| T3 | Grafana/Vault Internal 전환 | [T03-grafana-vault-internal.md](./2026-02-08-cluster-stabilization/T03-grafana-vault-internal.md) |
| T4 | Vault HA 로드맵 문서화 | [T04-vault-ha-roadmap.md](./2026-02-08-cluster-stabilization/T04-vault-ha-roadmap.md) |
| T5 | ArgoCD/Rancher/Longhorn Internal | [T05-argocd-rancher-longhorn-internal.md](./2026-02-08-cluster-stabilization/T05-argocd-rancher-longhorn-internal.md) |
| T6 | Keycloak Split-Horizon | [T06-keycloak-split-horizon.md](./2026-02-08-cluster-stabilization/T06-keycloak-split-horizon.md) |
| T7 | Cilium CNI 검증 + 코드 정합 | [T07-cilium-cni-verification.md](./2026-02-08-cluster-stabilization/T07-cilium-cni-verification.md) |
| T8 | Keycloak WAF Protection | [T08-keycloak-waf-protection.md](./2026-02-08-cluster-stabilization/T08-keycloak-waf-protection.md) |
| T9 | Vault KMS Auto-Unseal | [T09-vault-kms-auto-unseal.md](./2026-02-08-cluster-stabilization/T09-vault-kms-auto-unseal.md) |
| T10 | ALBC NLB IP-mode 확인 | [T10-albc-nlb-ip-mode.md](./2026-02-08-cluster-stabilization/T10-albc-nlb-ip-mode.md) |
| T11 | Keycloak SSO Grafana OIDC | [T11-keycloak-sso-grafana.md](./2026-02-08-cluster-stabilization/T11-keycloak-sso-grafana.md) |

## 🎯 Goals

1. **T1**: CCM helm-install CrashLoopBackOff 제거
2. **T2**: Monitoring Prometheus OutOfSync → **완전 Synced** 달성
3. **T3**: Grafana/Vault Ingress → Internal NLB
4. **T4**: Vault HA 전환 로드맵 문서화
5. **T5**: ArgoCD/Rancher/Longhorn → Internal NLB (Public 노출 완전 차단)
6. **T6**: Keycloak Split-Horizon (Public 인증 API + Internal Admin Console)
7. **T7**: Cilium CNI/ENI mode 검증 + 코드 정합성
8. **T8**: Keycloak WAF-Equivalent Protection (nginx Rate Limit + CiliumNetworkPolicy L7)
9. **T9**: Vault AWS KMS Auto-Unseal (Shamir → KMS 마이그레이션)
10. **T10**: ALBC NLB IP-mode 확인 (Cilium ENI VPC-native Pod IP)
11. **T11**: Keycloak SSO Grafana 연동 (OIDC generic_oauth)

## 📊 진행 결과

### T1: CCM CrashLoopBackOff 정리 ✅
| 항목 | 결과 |
|------|------|
| HelmChart CR | ✅ 삭제 (`helm.cattle.io/v1 aws-cloud-controller-manager`) |
| Addon | ✅ 삭제 (`k3s.cattle.io/v1 aws-ccm`) |
| CrashLoop Pod | ✅ 강제 삭제 |
| 서버 매니페스트 | ✅ SSM 비활성화 (3 CP 노드 전부 `.disabled`) |

### T2: Monitoring OutOfSync → Synced ✅ (5-Blocker 해결)

| # | Blocker | Fix | Commit |
|---|---------|-----|--------|
| 1 | Webhook TLS 실패 | `admissionWebhooks.enabled: false` | `3cc6f30` |
| 2 | Prometheus CRD 검증 | `retentionSize: 20GiB` | `5fa28e5` |
| 3 | PVC 교체 실패 | ignoreDiff + Replace=true 제거 | `18ae624` |
| 4 | Webhook 경고 잔존 | JSON patch 클리어 | — |
| **5** | **영구 OutOfSync** | **`values` string 변환** | `2452fd4` |

### T3: Grafana/Vault Internal 전환 ✅
| 서비스 | 변경 | 커밋 |
|--------|------|------|
| Grafana | `nginx` → `nginx-internal` | `ffda789` |
| Vault | `nginx` → `nginx-internal` | `ffda789` |

### T4: Vault 보안 강화 (검토) ✅
| 항목 | 결과 |
|------|------|
| HA 로드맵 | Phase A: KMS Auto-Unseal → Phase B: Raft HA → Phase C: TLS E2E |
| 문서 | `docs/vault/vault-ha-transition-roadmap.md` (`a639e8f`) |

### T5: ArgoCD/Rancher/Longhorn Internal 전환 ✅
| 서비스 | 방식 | 커밋 |
|--------|------|------|
| Rancher | GitOps YAML `nginx-internal` | `067fd2a` |
| Longhorn | GitOps YAML `nginx-internal` | `067fd2a` |
| ArgoCD | Terraform variable default + `make apply` | `067fd2a` |

### T6: Keycloak Split-Horizon 적용 ✅
| Ingress | Class | 경로 | 커밋 |
|---------|-------|------|------|
| `keycloak-public` | `nginx` (Public) | `/realms`, `/resources`, `/js` | `893a212` |
| `keycloak-admin` | `nginx-internal` (Internal) | `/admin` | `893a212` |

### T7: Cilium CNI 검증 + 코드 정합성 ✅
| 항목 | 상태 |
|------|------|
| IPAM | `eni` (VPC-native) ✅ |
| Pod IP | `10.0.x.x` (overlay 없음) ✅ |
| kube-proxy | eBPF 대체 완료 ✅ |
| Hubble | Relay + UI Running ✅ |
| 변수 default 정합 | `cni=cilium`, `eni_mode=true`, `ccm=false` (`0687766`) |

### T8: Keycloak WAF-Equivalent Protection ✅
| 계층 | 보호 | 커밋 |
|------|------|------|
| nginx Rate Limit | 20 rps / 300 rpm / 10 conn | `7221364` |
| Security Headers | X-Frame-Options, XSS 등 5종 | `7221364` |
| CiliumNetworkPolicy L7 | Public → `/realms`,`/resources`,`/js`만 허용 | `7221364` |

### T9: Vault AWS KMS Auto-Unseal ✅
| 항목 | 상태 |
|------|------|
| KMS Key | `fcaa0e8d` (key rotation 활성) ✅ |
| IAM Policy | KMS Encrypt/Decrypt/DescribeKey → Node Role ✅ |
| Seal Migration | Shamir 5/3 → AWS KMS ✅ |
| Auto-Unseal | Pod 재시작 → 자동 unseal 검증 ✅ |
| IMDS hop_limit | 1→2 (Cilium ENI Pod IMDS 접근) ✅ |

### T10: ALBC NLB IP-mode 확인 ✅ (이미 적용)
| 항목 | 상태 |
|------|------|
| NLB target-type | `ip` (Public + Internal) ✅ |
| TargetGroupBindings | 4개 모두 `ip` mode ✅ |
| Pod IP | VPC CIDR `10.0.x.x` (Cilium ENI) ✅ |
| ALBC | 2/2 Running + Vault Agent Sidecar ✅ |

### T11: Keycloak SSO Grafana 연동 ✅
| 항목 | 상태 |
|------|------|
| Keycloak Realm | `platform` (이미 존재) ✅ |
| OIDC Client | `grafana` (secret: `cb3ac87e`) ✅ |
| Protocol Mappers | `groups` claim (admin/editor/viewer) ✅ |
| Grafana.ini | `assertNoLeakedSecrets: false` + 직접 `client_secret` ✅ |
| Login Button | "Sign in with Keycloak" ✅ |
| ⚠️ Issue | Helm v7.1+ `assertNoLeakedSecrets`가 configmap에서 secret 제거 → 비활성화 |

## 📋 최종 Ingress 현황

| 서비스 | Class | NLB | WAF |
|--------|-------|-----|-----|
| Keycloak 인증 API | `nginx` | **Public** | nginx Rate Limit + CiliumNetworkPolicy L7 |
| Keycloak Admin | `nginx-internal` | Internal | — |
| ArgoCD | `nginx-internal` | Internal | — |
| Rancher | `nginx-internal` | Internal | — |
| Longhorn | `nginx-internal` | Internal | — |
| Grafana | `nginx-internal` | Internal | — |
| Vault | `nginx-internal` | Internal | — |

## 📋 Tasks

- [x] T1: CCM HelmChart/Addon/Pod/매니페스트 정리
- [x] T2: Monitoring 5-blocker 해결 (Root Cause: valuesObject)
- [x] T3: Grafana/Vault ingressClassName nginx-internal
- [x] T4: Vault HA 전환 로드맵 문서화
- [x] T5: ArgoCD/Rancher/Longhorn Internal NLB 전환
- [x] T6: Keycloak Split-Horizon (Public 인증 + Internal Admin)
- [x] T7: Cilium CNI 검증 + variables.tf 정합성
- [x] T8: Keycloak WAF (nginx Rate Limit + CiliumNetworkPolicy L7)
- [x] T9: Vault KMS Auto-Unseal + IMDS hop_limit 보안
- [x] T10: ALBC NLB IP-mode 확인 (이미 적용)
- [x] T11: Keycloak SSO Grafana (assertNoLeakedSecrets + OIDC)
- [x] 13/13 ArgoCD 앱 Synced + Healthy 확인

## 🔧 주요 변경 파일

| 범주 | 파일 |
|------|------|
| GitOps | `gitops-apps/bootstrap/monitoring.yaml` — 5-blocker fix |
| GitOps | `gitops-apps/bootstrap/rancher.yaml` — nginx-internal |
| GitOps | `gitops-apps/bootstrap/longhorn.yaml` — nginx-internal |
| GitOps | `gitops-apps/keycloak-ingress/resources.yaml` — Split-Horizon |
| Terraform | `stacks/dev/55-bootstrap/variables.tf` — ArgoCD nginx-internal |
| Terraform | `stacks/dev/55-bootstrap/main.tf` — KMS Key + IAM Policy |
| Terraform | `stacks/dev/50-rke2/variables.tf` — Cilium defaults 정합 |
| Terraform | `modules/ec2-instance/main.tf` — IMDS hop_limit=2 |
| GitOps | `gitops-apps/bootstrap/monitoring.yaml` — Grafana OIDC SSO |
| GitOps | `gitops-apps/keycloak-ingress/keycloak-oidc-secret.yaml` — OIDC Secret |
| Docs | `docs/vault/vault-ha-transition-roadmap.md` |
| Docs | `docs/vault/vault-kms-auto-unseal.md` |

## 📎 References

- [Vault HA 로드맵](../vault/vault-ha-transition-roadmap.md)
- [Cilium 아키텍처](../architecture/17-cilium-cni-architecture.md)

## 🏷️ Labels

`ccm`, `monitoring`, `security`, `ingress`, `vault`, `cilium`, `keycloak`, `waf`, `kms`, `sso`, `oidc`, `stabilization`

## 📌 Priority / Status

**High** / ✅ 완료 (2026-02-08)
