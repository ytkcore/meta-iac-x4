# 운영 자동화 스크립트 추가 — ArgoCD Sync, Teleport Init, OpStart CLI

> **Status**: ✅ 완료  
> **Priority**: Medium  
> **Labels**: `scripts`, `automation`, `argocd`, `teleport`, `opstart`  
> **작업 기간**: 2026-02-10~11  
> **주요 커밋**: `2d2bd97`

---

## 📋 요약

운영 자동화를 위한 스크립트 3종 신규 추가 및 기존 스크립트 2종 개선.
ArgoCD 전체 앱 동시 Sync, Teleport admin 초기화, OpStart CLI 6단계 자동화.

---

## 📂 변경 파일

| 파일 | 변경 |
|:-----|:-----|
| `scripts/argocd/sync-all.sh` | [NEW] ArgoCD 전체 Application 동시 Sync (23줄) |
| `scripts/teleport/init-admin.sh` | [NEW] Teleport admin 사용자 초기화 (35줄) |
| `scripts/common/opstart.sh` | [NEW] OpStart CLI 6단계 자동화 (230줄) |
| `scripts/harbor/setup-proxy-cache.sh` | [MOD] Proxy Cache 설정 개선 |
| `scripts/keycloak/configure-realm.sh` | [MOD] Realm 설정 스크립트 갱신 |
| `scripts/keycloak/patch-albc-vpcid.sh` | [MOD] ALBC VPC ID 패치 개선 |

---

## ✅ 작업 내역

- [x] **1.1** `sync-all.sh` — ArgoCD 전체 앱 Sync (Reconciliation 강제)
- [x] **1.2** `init-admin.sh` — Teleport admin 사용자/역할 초기화
- [x] **1.3** `opstart.sh` — 6단계 CLI (build, push, deploy, verify, cleanup, status)
- [x] **2.1** Harbor Proxy Cache 설정 개선
- [x] **2.2** Keycloak realm/ALBC 스크립트 최신화

---

## 🔗 관련 티켓

- [opstart-k8s-deployment](2026-02-11-opstart-k8s-deployment.md) — OpStart CLI 활용
- [teleport-app-service-completion](2026-02-09-teleport-app-service-completion.md) — Teleport init 원형

---

## 📝 비고

- `sync-all.sh`는 클러스터 재구축 후 전체 앱 동시 배포에 사용
- `init-admin.sh`는 Teleport 초기 배포 후 1회 실행
- `opstart.sh`는 `make opstart` wrapper에서 호출
