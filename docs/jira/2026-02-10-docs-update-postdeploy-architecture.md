# 운영 문서 갱신 — Post-Deploy Guide + Architecture Docs + Harbor OIDC

> **Status**: ✅ 완료  
> **Priority**: Medium  
> **Labels**: `docs`, `post-deploy`, `architecture`, `harbor`, `oidc`  
> **작업 기간**: 2026-02-10~11  
> **주요 커밋**: `6c7053d`, `2d2bd97`, `0ce9e9a`

---

## 📋 요약

운영 문서 대규모 갱신: Post-deployment Operations Guide 전면 개정(620줄),
Architecture Evolution Story 신규 작성, Communication Standards 문서화,
Architecture Comparison Dashboard 추가, Harbor OIDC 연동 운영 가이드 신규 작성.

---

## 🎯 목표

1. Post-deployment Operations Guide 최신화 (시스템 변경 반영)
2. Architecture Evolution Story 문서화 (Phase 1~6 진화 히스토리)
3. Communication Standards 공식화
4. Architecture Comparison 인터랙티브 시각화 추가
5. Harbor OIDC 연동 운영 가이드 신규 작성

---

## 📂 변경 파일

| 파일 | 변경 | 커밋 |
|:-----|:-----|:-----|
| `docs/guides/post-deployment-operations-guide.md` | [MOD] 전면 개정 (620줄 변경) | `2d2bd97` |
| `docs/architecture/18-architecture-evolution-story.md` | [NEW] 374줄 — Phase별 진화 히스토리 | `2d2bd97` |
| `docs/architecture/00-communication-standards.md` | [NEW] 103줄 — 한국어 커뮤니케이션 표준 | `2d2bd97` |
| `docs/architecture/opsta-architecture-design.md` | [NEW] 159줄 — OpStart 아키텍처 설계 | `2d2bd97` |
| `docs/architecture/stack-diagram/architecture-comparison.html` | [NEW] 1,755줄 — 인터랙티브 비교 대시보드 | `0ce9e9a` |
| `docs/operations/harbor-oidc-setup.md` | [NEW] 107줄 — Harbor OIDC 연동 가이드 | `6c7053d` |

---

## ✅ 작업 내역

- [x] **1.1** Post-deployment Operations Guide 전면 개정 — Keycloak SSO, Teleport, Grafana 반영
- [x] **2.1** Architecture Evolution Story (18-) — Phase 1~6 진화 기록
- [x] **2.2** Communication Standards (00-) — 한국어/영어 혼용 규칙
- [x] **2.3** OpStart Architecture Design 문서
- [x] **2.4** Architecture Comparison 인터랙티브 HTML 대시보드 (1,755줄)
- [x] **3.1** Harbor OIDC 연동 운영 가이드 — Keycloak Client 설정 방법

---

## 🔗 관련 티켓

- [v05-source-freeze](2026-02-10-v05-source-freeze.md) — v0.5 프리징 동일 세션
- [architecture-evolution-milestones](2026-02-07-architecture-evolution-milestones.md) — 마일스톤 원본

---

## 📝 비고

- Post-deploy Guide는 최근 Jira 티켓 (Keycloak SSO, Teleport App Service, Kube Agent Pod) 내용을 반영
- Architecture Comparison HTML은 v0.3 → v0.5 인프라 진화를 인터랙티브로 시각화
- Harbor OIDC 가이드는 수동 설정 방법 (Admin UI → Keycloak Client 생성)
