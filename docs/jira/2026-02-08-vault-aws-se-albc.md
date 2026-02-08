# [INFRA] Vault AWS Secrets Engine — ALBC Workload Identity

## 📋 Summary

Vault AWS Secrets Engine을 통해 ALBC Pod에 **동적 STS 자격증명**을 주입한다.
기존 Node IAM Role 직접 부착 → Vault assumed_role 기반 STS 임시 자격증명으로 전환.

커밋: `aba9b9c`, `dfbd5e4`, `eec6c11`, `f8186e5`

## 🎯 Goals

1. Node IAM Role → ALBC 정책 직접 부착 **제거**
2. Vault AWS Secrets Engine → **STS 동적 자격증명** (15min TTL, 자동 rotation)
3. Vault Agent Sidecar → ALBC Pod에 credential 자동 주입
4. Keycloak OIDC 대신 **Vault K8s Auth** 기반 Workload Identity

## 📊 구현 결과

| 항목 | 값 |
|------|-----|
| ALBC Namespace | `aws-system` |
| Vault AWS Role | `albc` (assumed_role → `dev-meta-vault-albc-role`) |
| TTL | 15min default / 1h max |
| K8s Auth Role | `albc` (SA: `aws-load-balancer-controller`, NS: `aws-system`) |
| Credential Path | `/vault/secrets/aws-creds` |
| Pod Containers | 2/2 (controller + vault-agent sidecar) |
| TargetGroupBindings | 4개 정상 관리 |

## 📋 Tasks (완료)

### Terraform IAM
- [x] `dev-meta-vault-albc-role` IAM Role 생성 (Vault AssumeRole용)
- [x] Node Role → vault-albc-role `sts:AssumeRole` inline policy
- [x] ALBC policy → vault-albc-role 부착
- [x] `enable_vault_integration` toggle 추가
- [x] Phase 1 직접 부착 조건부 비활성화 (`count = enable_vault_integration ? 0 : 1`)
- [x] `terraform apply` — 3 리소스 생성 + 1 리소스 제거

### Vault 설정 (CLI)
- [x] `aws/` secrets engine 활성화
- [x] `aws/roles/albc` — credential_type=assumed_role, role_arns, TTL
- [x] `albc-aws-policy` Vault policy
- [x] `auth/kubernetes/role/albc` — K8s auth role (SA binding)

### GitOps
- [x] ALBC Helm — Vault Agent Injector annotations
- [x] ALBC namespace `kube-system` → `aws-system` (Injector 호환)
- [x] Vault Injector — `AGENT_INJECT_IGNORE_NAMESPACES: kube-public`
- [x] `AWS_SHARED_CREDENTIALS_FILE=/vault/secrets/aws-creds` env 설정

## ⚠️ 이슈 및 해결 (4건)

| # | Issue | Fix |
|---|-------|-----|
| 1 | `federation_token` 실패 | `assumed_role` type 전환 (Node Role에 GetFederationToken 없음) |
| 2 | IAM Tag Unicode `→` | AWS 태그 규격 위반 → ASCII 대체 |
| 3 | Vault Injector kube-system 거부 | ALBC → `aws-system` namespace 이동 |
| 4 | ArgoCD selfHeal 덮어쓰기 | Git push + root-apps hard refresh |

## 🔧 주요 변경 파일

| 범주 | 파일 |
|------|------|
| Terraform | `modules/albc-iam/main.tf`, `variables.tf`, `outputs.tf` |
| Terraform | `stacks/dev/50-rke2/main.tf` |
| GitOps | `gitops-apps/bootstrap/aws-load-balancer-controller.yaml` |
| GitOps | `gitops-apps/bootstrap/vault.yaml` |
| Docs | `docs/architecture/16-architecture-evolution-decision.md` |

## 📎 References

- [16-architecture-evolution-decision.md](../architecture/16-architecture-evolution-decision.md) — 아키텍처 의사결정
- [마일스톤 §Phase 3](2026-02-07-architecture-evolution-milestones.md) — Phase 3 상세

## 🏷️ Labels

`vault`, `aws-se`, `workload-identity`, `sts`, `albc`, `phase-3`

## 📌 Priority / Status

**High** / ✅ 완료 (2026-02-08)
