# v0.5 Source Code Freeze

> **Status**: ✅ 완료  
> **Priority**: Critical  
> **Labels**: `release`, `v0.5`, `source-freeze`, `milestone`  
> **적용일**: 2026-02-10  
> **커밋**: `c0b023a` — `v0.5: Source Code Freeze`  
> **태그**: `v0.5`

---

## 📋 요약

플랫폼 v0.5 소스 코드 프리징을 수행한다.
Customer Services, Disaster Recovery, Architecture 문서를 포함한
18개 파일(+2,579 lines)의 변경사항을 커밋하고 `v0.5` Git 태그를 생성한다.

---

## 🎯 목표

1. 모든 v0.5 소스 코드 변경사항 커밋 및 태그
2. Customer Services 2개 서비스 소스 코드 확정
3. Velero DR 구성 소스 코드 확정
4. SSO 연동 현황 정리
5. Platform Maturity Strategy 문서 추가

---

## 📂 변경 파일 (18 files, +2,579 lines)

| Category | Files | Type |
|:---------|:------|:-----|
| Platform Dashboard | 7 files (src + k8s + ArgoCD App) | NEW |
| Landing Page | 7 files (src + k8s + ArgoCD App) | NEW |
| Velero DR | 1 file (ArgoCD App) | NEW |
| Terraform | 2 files (main.tf + variables.tf) | MOD |
| Architecture | 1 file (maturity strategy) | NEW |

---

## ✅ 작업 내역

- [x] **1.1** Platform Dashboard 전체 구현 + 브라우저 검증
- [x] **1.2** Landing Page 전체 구현 + 브라우저 검증
- [x] **2.1** Velero ArgoCD App + Terraform S3/IAM
- [x] **3.1** ArgoCD OIDC 상태 확인 (이미 구성됨)
- [x] **3.2** Grafana OIDC 상태 확인 (이미 운영 중)
- [x] **4.1** `20-platform-maturity-strategy.md` 작성
- [x] **5.1** Git commit `c0b023a`
- [x] **5.2** Git tag `v0.5`
- [x] **5.3** Remote push (main + tags)

---

## 📊 v0.5 플랫폼 현황

| Metric | Value |
|:-------|:------|
| Terraform Stacks | 14 |
| ArgoCD Apps | 15 (13 기존 + 2 신규) |
| Identity Layers | 3 (Keycloak + Vault + Teleport) |
| Observability Pillars | 3 (Prometheus + Loki + Tempo) |
| SSO 연동 | ArgoCD ✅, Grafana ✅, Harbor 📋 |

---

## 🔗 관련 티켓 / 문서

- [velero-disaster-recovery](2026-02-10-velero-disaster-recovery.md) — DR 상세
- [customer-services-deployment](2026-02-10-customer-services-deployment.md) — 서비스 상세
- [architecture-evolution-milestones](2026-02-07-architecture-evolution-milestones.md) — 아키텍처 진화
- [cluster-stabilization](2026-02-08-cluster-stabilization.md) — 클러스터 안정화

---

## 📝 비고

- Post-deploy 필수: `70-observability` Terraform apply (Velero S3 버킷), DNS Record 생성
- Harbor OIDC는 Admin UI에서 수동 설정 필요
- `env.tfvars` 변경은 `.gitignore` 대상이므로 별도 관리
