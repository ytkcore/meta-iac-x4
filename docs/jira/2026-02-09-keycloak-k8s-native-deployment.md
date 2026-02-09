# [INFRA] Keycloak EC2 → K8s-native Deployment 실행

## 📋 Summary

Keycloak을 EC2(Docker Compose)에서 **K8s Deployment(ArgoCD GitOps)**로 전환 완료.
Helm 대신 Raw YAML 매니페스트를 사용하여 투명한 설정 관리 달성.

## 🎯 Goals

1. **EC2 의존 제거**: Docker Compose → K8s Deployment
2. **ArgoCD GitOps 관리체계 편입**: `keycloak-ingress` Application
3. **DB 연속성 유지**: 기존 60-postgres(self-managed) 재활용
4. **Health Probe 정상화**: Keycloak v25 management port(9000) 적용

## 📋 Tasks

- [x] **1.1** PostgreSQL keycloak user 비밀번호 리셋 (`setup-keycloak-db.sh`)
- [x] **1.2** `keycloak-deployment.yaml` 작성 (Deployment + DB Secret + Admin Secret)
- [x] **1.3** `resources.yaml` — 수동 Endpoints 삭제, Service selector 추가
- [x] **1.4** ArgoCD sync 확인 (Synced / Healthy)
- [x] **1.5** Health probe port 수정 (8080 → 9000, Keycloak v25 management port)
- [x] **1.6** OIDC Discovery endpoint 동작 확인 (HTTP 200)

## 🔧 변경 파일

| 파일 | 변경 |
|------|------|
| `gitops-apps/keycloak-ingress/keycloak-deployment.yaml` | **신규** — Deployment + Secrets |
| `gitops-apps/keycloak-ingress/resources.yaml` | Service selector 추가, Endpoints 삭제 |

## 📎 Commits

| Hash | 설명 |
|------|------|
| `370d4fe` | Keycloak K8s-native deployment 초기 |
| `570b05e` | Health probe port 9000 수정 |

## 🔗 Dependencies

- `2026-02-08-keycloak-k8s-migration.md` — 계획 티켓 (이 티켓이 실행본)
- `60-postgres` — 외부 PostgreSQL DB

## 🏷️ Labels

`keycloak`, `k8s-migration`, `argocd`, `execution`

## 📌 Priority / Status

**Critical** | ✅ **Done**
