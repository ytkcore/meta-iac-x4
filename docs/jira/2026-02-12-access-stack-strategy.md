# Teleport 대체 — Zero-Trust 접근 제어 스택 전략 수립

> **날짜**: 2026-02-12  
> **상태**: 📋 전략 확정 (구현 미착수)  
> **라벨**: `architecture`, `security`, `v0.6-planning`  
> **우선순위**: High

---

## 배경

Teleport CE의 AGPL-3.0 라이선스가 상용 제품 패키징을 제한. 허용적 라이선스(Apache 2.0) 기반 대안을 조사하고, On-prem 고객 지원을 위한 CSP 독립적 접근 전략을 수립.

## 목표

- Teleport 기능별 Apache 2.0 대안 확정
- SSH-less 운영 모델 설계
- CSP별 접근 전략(AWS SSM, GCP IAP, Azure Bastion, On-prem) 정리

## 의사결정 사항

| 역할 | 현재 (Teleport) | 대안 (확정) | 라이선스 |
|------|:---:|:---:|:---:|
| SSO/IdP | Keycloak | **Keycloak** (유지) | Apache 2.0 |
| App Access (웹 UI 프록시) | Teleport App Access | **Pomerium** | Apache 2.0 |
| K8s kubectl | SSM → Bastion | **Rancher Shell** (이미 배포) | Apache 2.0 |
| VM/서버 리모트 접근 | SSM Session Manager | **ShellHub** (평가 중) | Apache 2.0 |
| 노드 OS 디버깅 | SSH | `kubectl debug node/` | K8s 내장 |

### 조사 결과 — 탈락 후보

| 후보 | 탈락 사유 |
|------|---------|
| NetBird | BSD-3 → AGPL-3.0 전환 (2025-08) |
| Octelium | 서버 AGPL-3.0 |
| Cockpit | LGPL-2.1, 중앙 관리 부재 |

### CSP별 접근 전략

| 환경 | VM 리모트 접근 | 비고 |
|------|:---:|------|
| AWS | ShellHub (통합) 또는 SSM (네이티브) | 고객 선택 |
| GCP | ShellHub (통합) 또는 IAP (네이티브) | 고객 선택 |
| Azure | ShellHub (통합) 또는 Bastion (네이티브) | 고객 선택 |
| **On-Prem** | **ShellHub (필수)** | CSP 도구 없음 |

## 산출물

- `00-csp-independence-todo.md` 섹션 11 추가 (17개 TODO 항목)
- ShellHub/MeshCentral PoC 평가 기준 정의

## 참조

- [00-csp-independence-todo.md §11](../architecture/00-csp-independence-todo.md)
