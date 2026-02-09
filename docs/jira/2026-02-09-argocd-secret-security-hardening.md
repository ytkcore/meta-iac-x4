# [SEC] ArgoCD Secret 보안 강화 — Prune 방지 + 평문 비밀번호 제거

## 📋 Summary

Keycloak 및 Grafana OIDC Secret에 저장된 **평문 비밀번호를 Git에서 제거**하고,
ArgoCD의 `prune: true` 설정으로 인한 **Secret 삭제 위험을 방지**하는 보안 강화 작업.

## 🎯 Goals

1. **평문 비밀번호 Git 노출 제거**: DB 비밀번호, Admin 비밀번호, OIDC Client Secret
2. **ArgoCD prune 안전장치**: `ignoreDifferences` + `RespectIgnoreDifferences=true`
3. **운영 가이드 보강**: Secret 사전 생성 절차 및 보안 체크리스트 확대

## 📋 Tasks

- [x] **T1** `keycloak-deployment.yaml` — 평문 Secret → `CHANGE_ME` placeholder 교체
- [x] **T1** `keycloak-ingress.yaml` — `ignoreDifferences` (Secret /data, /stringData) 추가
- [x] **T1** `keycloak-ingress.yaml` — `RespectIgnoreDifferences=true` syncOption 추가
- [x] **T2** `keycloak-oidc-secret.yaml` — Grafana Client Secret 평문 → placeholder
- [x] **가이드** `post-deployment-operations-guide.md` §1.0 Secret 사전 생성 절차 추가
- [x] **가이드** `post-deployment-operations-guide.md` §10 보안 체크리스트 6→9항목 확대

## 🔧 변경 파일

| 파일 | 변경 |
|------|------|
| `gitops-apps/keycloak-ingress/keycloak-deployment.yaml` | Secret stub CHANGE_ME + 주석 가이드 |
| `gitops-apps/bootstrap/keycloak-ingress.yaml` | ignoreDifferences + RespectIgnoreDifferences |
| `gitops-apps/keycloak-ingress/keycloak-oidc-secret.yaml` | 평문 Client Secret → CHANGE_ME |
| `docs/guides/post-deployment-operations-guide.md` | §1.0, §10 보강, 변경이력 v1.1 |

## 📎 Commits

| Hash | 설명 |
|------|------|
| `2547651` | Keycloak 평문 비밀번호 제거 + 가이드 보강 |
| `631656d` | ArgoCD ignoreDifferences + Secret placeholder |

## ⚠️ 주의사항

- ArgoCD `ignoreDifferences`가 bootstrap App sync 후 반영되어야 Secret 값 보존
- Git 히스토리에 평문 비밀번호 잔존 → Prod 전환 전 BFG Repo-Cleaner 필요

## 🏷️ Labels

`security`, `argocd`, `secret-management`, `keycloak`

## 📌 Priority / Status

**Critical** | ✅ **Done**
