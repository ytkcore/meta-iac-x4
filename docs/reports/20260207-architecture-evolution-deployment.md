# Architecture Evolution — Deployment Report

> **Date**: 2026-02-07  
> **Commit**: `49544ff` (30 files, +2228 lines)  
> **Scope**: Phase 1 (ALBC IAM) + Phase 2 (Keycloak SSO)

---

## 1. Applied Stacks

| Stack | Operation | Resources |
|-------|-----------|-----------|
| `50-rke2` | 2 add, 1 change | ALBC IAM Policy + Node Role attachment, VPC ID output |
| `25-keycloak` | 7 add | EC2, Security Group, IAM Role/Profile, Route53 A record |
| `55-bootstrap` | 3 change | ArgoCD OIDC values, infra-context secret, root-app |

---

## 2. Infrastructure State

### 2.1 ALBC IAM Policy (Phase 1)

| Item | Value |
|------|-------|
| Policy ARN | `arn:aws:iam::599913747911:policy/dev-meta-albc-policy` |
| Attached To | `dev-meta-k8s-role` (Node IAM Role) |
| VPC ID | `vpc-0f00997f25423fdab` |

### 2.2 Keycloak EC2 (Phase 2)

| Item | Value |
|------|-------|
| Instance ID | `i-014b6fd348c899cc2` |
| Private IP | `10.0.101.201` |
| Security Group | `sg-0c1c9e79379e93738` |
| DNS Record | `keycloak.dev.unifiedmeta.net` → `10.0.101.201` |
| Keycloak Version | 25.0.6 (Quarkus 3.8.5) |
| HTTPS Port | 8443 (self-signed cert) |
| Database | PostgreSQL `10.0.1.24:5432/keycloak` (user: `keycloak`) |

### 2.3 Keycloak Realm Configuration

- **Realm**: `platform`
- **Groups**: `admin`, `editor`, `developer`, `viewer`
- **Admin User**: `platform-admin` (임시 비밀번호, 첫 로그인 시 변경 필수)

#### OIDC Clients

| Client ID | Redirect URI | Secret |
|-----------|-------------|--------|
| `grafana` | `https://grafana.unifiedmeta.net/*` | `cb3ac87e35b9560110b2667e43bcc503` |
| `argocd` | `https://argocd.unifiedmeta.net/*` | `207f453ce3051a1e05de0550418818c6` |
| `rancher` | `https://rancher.unifiedmeta.net/*` | `d3f254ba49f4a2ed0a963fc2b491b737` |
| `harbor` | `https://harbor.unifiedmeta.net/*` | `08743ab5ecbe9e26a5b67541a88d3317` |
| `teleport` | `https://teleport.unifiedmeta.net/*` | `bb4f76c8d5329bc1dd634aba3e4e2d22` |

> [!IMPORTANT]
> Client secrets는 `scripts/keycloak/client-secrets.env`에도 저장됨 (gitignored)

---

## 3. New Modules & Files

### Terraform Modules
- `modules/albc-iam/` — AWS Load Balancer Controller IAM Policy
- `modules/keycloak-ec2/` — Keycloak EC2 (Docker Compose + self-signed TLS)

### Terraform Stack
- `stacks/dev/25-keycloak/` — Keycloak 스택 (EC2, SG, IAM, DNS, OIDC Provider stub)

### GitOps Apps
- `gitops-apps/bootstrap/aws-load-balancer-controller.yaml` — ALBC ArgoCD App
- `gitops-apps/bootstrap/vault.yaml` — Vault ArgoCD App (Phase 4 stub)

### Automation Scripts
- `scripts/keycloak/setup-keycloak-db.sh` — PostgreSQL DB 자동 생성 (SSM)
- `scripts/keycloak/configure-realm.sh` — Realm + OIDC Clients 자동 구성
- `scripts/keycloak/patch-albc-vpcid.sh` — ALBC yaml VPC ID 패치
- `scripts/keycloak/deploy-evolution.sh` — 5 Phase 배포 오케스트레이터

---

## 4. Deployment Issues & Fixes

| # | Issue | Root Cause | Fix |
|---|-------|-----------|-----|
| 1 | Keycloak TLS key 읽기 실패 | `server.key` 파일 권한 `600` (root only) | `chmod 644` (keycloak container user readable) |
| 2 | Keycloak Admin 인증 실패 | `KC_BOOTSTRAP_ADMIN_USERNAME` (v26+ 전용) | `KEYCLOAK_ADMIN` (v25 호환) 으로 변경 |
| 3 | DB 연결 실패 | 수동 생성 password vs Terraform output mismatch | `ALTER ROLE` + DB 재생성으로 sync |

> [!TIP]
> `modules/keycloak-ec2/templates/user-data.sh.tftpl` 에 위 3가지 수정사항 모두 반영 완료.
> 다음 배포(재생성)부터는 자동 적용됨.

---

## 5. Phase 4: Vault

| Item | Value |
|------|-------|
| Helm Chart | `hashicorp/vault` v0.28.1 |
| Namespace | `vault` |
| vault-0 | **1/1 Running** (Unsealed) |
| vault-agent-injector | 1/1 Running |
| Version | 1.17.2 |
| Cluster | `vault-cluster-837dca17` |
| Vault Service | `10.43.223.245:8200` (ClusterIP) |
| Ingress | `vault.dev.unifiedmeta.net` (nginx class) |

### Auth Methods

| Path | Type | 용도 |
|------|------|------|
| `oidc/` | OIDC | Keycloak `platform` realm 연동 |
| `kubernetes/` | Kubernetes | Pod 인증 (ServiceAccount) |
| `token/` | Token | 기본 토큰 인증 |

### Secrets Engines

| Path | Type | 용도 |
|------|------|------|
| `secret/` | KV-v2 | 정적 시크릿 저장 |
| `database/` | Database | PostgreSQL dynamic credentials |

### OIDC Roles

| Role | Audiences | Policies | 비고 |
|------|-----------|----------|------|
| `default` | argocd | default | 일반 사용자 |
| `admin` | argocd | admin | 전체 관리 권한 |

### Vault 접근 방법

```bash
kubectl --kubeconfig ~/.kube/config-rke2-dev port-forward svc/vault 8200:8200 -n vault
# http://localhost:8200 (OIDC 로그인 가능)
```

### Vault Unseal (재시작 시)

```bash
kubectl --kubeconfig ~/.kube/config-rke2-dev exec -it vault-0 -n vault -- vault operator init
kubectl --kubeconfig ~/.kube/config-rke2-dev exec -it vault-0 -n vault -- vault operator unseal <key>
```

> [!WARNING]
> Unseal keys와 root token은 `scripts/keycloak/vault-keys.env`에 저장됨 (gitignored).
> 반드시 안전한 장소에 백업할 것.

---

## 6. ALBC Webhook Issue

ALBC 배포 시 `vingress.elbv2.k8s.aws` admission webhook이 자동 생성되어,
모든 Ingress 리소스에 대해 IngressClass 검증을 수행함.

**영향**: `nginx` class의 Ingress도 ALBC webhook이 가로채서 검증 → `nginx-internal` class가 없으면 차단.

**해결**: Vault ingress를 disable하고 `kubectl port-forward` 또는 Teleport App Access로 접근.
향후 webhook의 `objectSelector`를 수정하여 ALB class만 검증하도록 변경 가능.

---

## 7. ArgoCD Applications Status

| App | Sync | Health |
|-----|------|--------|
| aws-load-balancer-controller | ✅ Synced | ✅ Healthy |
| cert-manager | ✅ Synced | ✅ Healthy |
| nginx-ingress | ✅ Synced | ✅ Healthy |
| nginx-ingress-internal | ✅ Synced | ✅ Healthy |
| rancher | ✅ Synced | ✅ Healthy |
| root-apps | ✅ Synced | ✅ Healthy |
| vault | ⚠️ OutOfSync | ⬜ Missing |
| monitoring | ⚠️ OutOfSync | ✅ Healthy |
| longhorn | ⚠️ OutOfSync | ✅ Healthy |

---

## 8. Remaining Phases

| Phase | Status | Next Action | 비고 |
|-------|--------|-------------|------|
| Phase 3: OIDC Federation | ⏸️ 보류 | Keycloak 공개 endpoint 필요 | private-only 현재 |
| Phase 4: DB Secret 구성 | ⏳ | `database/` engine에 PG 연결 설정 | unseal key 보관 후 |
| Phase 5: CCM 제거 | ⏸️ 보류 | CCM이 Node lifecycle 관리 중 | 별도 유지보수 창 |

> [!NOTE]
> Phase 3 (OIDC Federation): AWS IAM이 OIDC discovery endpoint에 접근 필요. Keycloak이 private subnet에만 있어 보류.
> Phase 5 (CCM 제거): CCM이 `--cloud-provider=external` 모드에서 Node lifecycle(주소/라벨/taint) 관리 중. 제거 시 Node 초기화 위험 → 별도 유지보수 창에서 신중하게 진행 필요.
