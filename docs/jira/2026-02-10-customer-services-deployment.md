# Customer Services 배포 — Platform Dashboard & Landing Page

> **Status**: ✅ 완료  
> **Priority**: Medium  
> **Labels**: `customer-services`, `gitops`, `frontend`, `argocd`  
> **적용일**: 2026-02-10  
> **커밋**: `c0b023a` — `v0.5: Source Code Freeze`

---

## 📋 요약

두 개의 대고객 서비스를 구축한다:
1. **Platform Overview Dashboard** (`dashboard.unifiedmeta.net`) — 플랫폼 아키텍처 인터랙티브 시각화
2. **Product Landing Page** (`www.unifiedmeta.net`) — UnifiedMeta 제품 소개 웹사이트

Static HTML/CSS/JS → Nginx 컨테이너 → Kustomize ConfigMap → ArgoCD Application 구조로 배포한다.

---

## 🎯 목표

1. Platform Dashboard: 6계층 아키텍처 다이어그램, 24개 컴포넌트 상세 패널
2. Landing Page: Hero, Features, Architecture, Tech Stack, CTA 섹션
3. ArgoCD Application 매니페스트로 GitOps 자동 배포
4. Kustomize ConfigMap Generator로 HTML/CSS/JS 파일 서빙
5. Ingress + cert-manager TLS (letsencrypt-prod)

---

## 📂 변경 파일

### Platform Dashboard

| 파일 | 변경 |
|:-----|:-----|
| `gitops-apps/apps/platform-dashboard/src/index.html` | [NEW] 아키텍처 시각화 HTML |
| `gitops-apps/apps/platform-dashboard/src/style.css` | [NEW] Dark mode + glassmorphism |
| `gitops-apps/apps/platform-dashboard/src/app.js` | [NEW] 24 컴포넌트 인터랙션 |
| `gitops-apps/apps/platform-dashboard/Dockerfile` | [NEW] Nginx Alpine |
| `gitops-apps/apps/platform-dashboard/k8s/deployment.yaml` | [NEW] Deploy + Service + Ingress |
| `gitops-apps/apps/platform-dashboard/k8s/kustomization.yaml` | [NEW] ConfigMap Generator |
| `gitops-apps/bootstrap/platform-dashboard.yaml` | [NEW] ArgoCD Application |

### Landing Page

| 파일 | 변경 |
|:-----|:-----|
| `gitops-apps/apps/landing-page/src/index.html` | [NEW] 제품 소개 HTML |
| `gitops-apps/apps/landing-page/src/style.css` | [NEW] Premium dark mode + gradient orbs |
| `gitops-apps/apps/landing-page/src/app.js` | [NEW] Scroll 애니메이션 |
| `gitops-apps/apps/landing-page/Dockerfile` | [NEW] Nginx Alpine |
| `gitops-apps/apps/landing-page/k8s/deployment.yaml` | [NEW] Deploy + Service + Ingress |
| `gitops-apps/apps/landing-page/k8s/kustomization.yaml` | [NEW] ConfigMap Generator |
| `gitops-apps/bootstrap/landing-page.yaml` | [NEW] ArgoCD Application |

---

## ✅ 작업 내역

- [x] **1.1** Platform Dashboard HTML/CSS/JS 구현
- [x] **1.2** 24개 컴포넌트 상세 데이터 (Keycloak, Vault, Teleport, ArgoCD 등)
- [x] **1.3** Dashboard Dockerfile + K8s 매니페스트 + Kustomization
- [x] **2.1** Landing Page HTML/CSS/JS 구현
- [x] **2.2** Hero, Features, Architecture, Tech Stack 섹션
- [x] **2.3** Landing Page Dockerfile + K8s 매니페스트 + Kustomization
- [x] **3.1** ArgoCD Application 매니페스트 2개 작성
- [x] **3.2** 브라우저 시각 검증 ✅

---

## 🔗 관련 티켓 / 문서

- [velero-disaster-recovery](2026-02-10-velero-disaster-recovery.md) — 동일 커밋 DR 설정
- [v0.5-source-freeze](2026-02-10-v05-source-freeze.md) — v0.5 프리징
- [web-service-onboarding](2026-02-07-web-service-onboarding.md) — 웹 서비스 온보딩 표준

---

## 📝 비고

- Post-deploy: `dashboard.unifiedmeta.net`, `www.unifiedmeta.net` DNS A Record 생성 필요
- Deployment는 ConfigMap Volume Mount 방식 (CI/CD 파이프라인 불필요 — Git Push → ArgoCD Sync)
- Dashboard 컴포넌트 데이터는 실제 플랫폼 구성을 정확히 반영
- 두 서비스 모두 `apps` 네임스페이스에 배포, 2 replicas
