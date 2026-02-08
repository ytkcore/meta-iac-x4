# [INFRA] Architecture Evolution Phase 1-2-4 실제 배포 — ALBC + Keycloak + Vault

## 📋 Summary

Architecture Evolution 의사결정에 따라 **Phase 1(ALBC IAM), Phase 2(Keycloak SSO), Phase 4(Vault)**를
실제 인프라에 배포하고 서비스를 구성한다.

커밋: `49544ff` (30 files, +2228 lines)

## 🎯 Goals

1. **Phase 1**: ALBC IAM Policy 생성 + Node Role 연결
2. **Phase 2**: Keycloak EC2 배포 + OIDC Client 5개 자동 구성
3. **Phase 4**: Vault Helm 배포 + OIDC/K8s Auth + Database Secrets Engine
4. **자동화 스크립트**: DB 생성, Realm 구성, 배포 오케스트레이터

## 📊 배포 결과

### Phase 1: ALBC IAM
| Item | Value |
|------|-------|
| Policy | `dev-meta-albc-policy` |
| Attached To | `dev-meta-k8s-role` |
| VPC ID | `vpc-0f00997f25423fdab` |

### Phase 2: Keycloak EC2
| Item | Value |
|------|-------|
| Instance | `i-014b6fd348c899cc2` (10.0.101.201) |
| DNS | `keycloak.dev.unifiedmeta.net` |
| Version | 25.0.6 (Quarkus) |
| Realm | `platform` |
| Groups | admin, editor, developer, viewer |
| OIDC Clients | grafana, argocd, rancher, harbor, teleport |

### Phase 4: Vault
| Item | Value |
|------|-------|
| Version | 1.17.2 |
| Status | Unsealed (5 shares, threshold 3) |
| Auth | OIDC (Keycloak), Kubernetes, Token |
| Secrets | KV-v2 (`secret/`), Database (`database/`) |
| Ingress | `vault.dev.unifiedmeta.net` |

## 📋 Tasks (완료)

### Terraform 모듈 신규
- [x] `modules/albc-iam/` — ALBC IAM Policy 모듈
- [x] `modules/keycloak-ec2/` — Keycloak EC2 (Docker Compose + self-signed TLS)
- [x] `stacks/dev/25-keycloak/` — Keycloak 스택 (EC2, SG, IAM, DNS)

### Keycloak 구성
- [x] PostgreSQL DB 자동 생성 (`scripts/keycloak/setup-keycloak-db.sh`)
- [x] Realm + OIDC Clients 자동 구성 (`scripts/keycloak/configure-realm.sh`)
- [x] OIDC Client 5개 생성 (grafana, argocd, rancher, harbor, teleport)
- [x] TLS 인증서 파일 권한 문제 해결 (`chmod 644`)
- [x] `KC_BOOTSTRAP_ADMIN_USERNAME` → `KEYCLOAK_ADMIN` (v25 호환)

### Vault 배포
- [x] `gitops-apps/bootstrap/vault.yaml` — Vault ArgoCD App
- [x] Vault unseal (5 shares, threshold 3)
- [x] OIDC Auth (Keycloak `platform` realm 연동)
- [x] Kubernetes Auth (ServiceAccount 인증)
- [x] Database Secrets Engine (PostgreSQL dynamic creds 검증)

### ALBC 설정
- [x] `gitops-apps/bootstrap/aws-load-balancer-controller.yaml`
- [x] `webhookConfig.disableIngressValidation` — nginx class Ingress 충돌 해결
- [x] ALBC VPC ID 패치 스크립트

### 배포 자동화
- [x] `scripts/keycloak/deploy-evolution.sh` — 5 Phase 오케스트레이터
- [x] `scripts/keycloak/patch-albc-vpcid.sh` — VPC ID 자동 패치

## ⚠️ 배포 이슈 및 해결

| # | Issue | Fix |
|---|-------|-----|
| 1 | Keycloak TLS key 권한 | `chmod 644` (container user readable) |
| 2 | Admin 인증 실패 | `KEYCLOAK_ADMIN` (v25 호환) |
| 3 | DB 연결 mismatch | `ALTER ROLE` + DB 재생성 |
| 4 | ALBC webhook 충돌 | `disableIngressValidation` 설정 |

## 🔧 주요 변경 파일 (30 files, +2228)

| 범주 | 파일 |
|------|------|
| ALBC 모듈 | `modules/albc-iam/` |
| Keycloak 모듈 | `modules/keycloak-ec2/` |
| Keycloak 스택 | `stacks/dev/25-keycloak/` |
| GitOps | `vault.yaml`, `aws-load-balancer-controller.yaml` |
| 스크립트 | `scripts/keycloak/` (4파일) |

## 📎 References

- [배포 리포트](../reports/20260207-architecture-evolution-deployment.md) — 상세 결과
- [16-architecture-evolution-decision.md](../architecture/16-architecture-evolution-decision.md) — 의사결정 근거
- [2026-02-07-architecture-evolution-milestones.md](2026-02-07-architecture-evolution-milestones.md) — 마일스톤

## 🏷️ Labels

`albc`, `keycloak`, `vault`, `phase-1`, `phase-2`, `phase-4`, `deployment`

## 📌 Priority / Status

**Critical** / ✅ 완료 (2026-02-07~08)
