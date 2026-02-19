# Post-Deployment 운영 가이드 글로벌 표준 개선

> **Status**: ✅ 완료  
> **Priority**: High  
> **Labels**: `operations`, `security`, `global-standard`, `documentation`  
> **작업 기간**: 2026-02-12  

---

## 📋 요약

Post-Deployment Operations Guide(v2.0)를 글로벌 스탠다드(Helm NOTES.txt, CIS Benchmark, NIST 800-63B, Google SRE, HashiCorp Best Practices, AWS Well-Architected)와 비교 분석하여 6개 개선 항목을 식별하고 적용.

---

## 🎯 목표

1. 초기 비밀번호 자동 디스커버리 체계 구축 (Helm NOTES.txt 패턴)
2. 첫 로그인 시 비밀번호 강제 변경 절차 명문화
3. Secret Rotation 정책 수립
4. 배포 후 Smoke Test 자동화 가이드
5. 초기화 실패 시 Rollback 절차 추가
6. Keycloak Client Secret → Vault 중앙 관리 패턴 적용

---

## 📂 변경 파일

| 파일 | 변경 |
|:-----|:-----|
| `docs/guides/post-deployment-operations-guide.md` | [MOD] 6개 글로벌 표준 개선 항목 반영 |

---

## 🔍 글로벌 표준 Gap 분석

### 1. Credential Discovery — Helm NOTES.txt 패턴

- **글로벌 표준**: `helm install` 완료 시 NOTES.txt로 credential 조회법 자동 출력. 모든 CNCF Helm Chart가 이 패턴 사용
- **현재 문제**: ArgoCD GitOps 환경에서는 `helm install` 직접 실행 안 함 → NOTES.txt 미출력
- **개선**: 각 서비스별 `kubectl get secret` 원라이너를 Quick Reference 테이블로 문서 상단에 집중 배치
- **향후**: `make credentials` 명령어로 자동 출력 구현

### 2. First-Login Force Change — Rancher/Grafana 패턴

- **글로벌 표준**: 첫 로그인 시 비밀번호 변경 강제 (Rancher: bootstrap PW, Grafana: `admin_password` 초기화)
- **현재 문제**: "변경하세요"만 기재, 강제 메커니즘 없음
- **개선**: Keycloak `Temporary Password` 옵션 활성화 절차 추가, 서비스별 강제 변경 메커니즘 문서화

### 3. Secret Rotation — NIST 800-63B

- **글로벌 표준**: 초기 자격증명은 제한된 수명(TTL) 보유, 일정 기간 후 자동 만료
- **현재 문제**: 초기 비밀번호 무기한 유효
- **개선**: Vault TTL 기반 Secret 만료 정책 가이드 추가

### 4. Smoke Test — Google SRE Playbook

- **글로벌 표준**: 배포 후 자동화된 헬스체크 실행 (readiness gate, post-deploy hook)
- **현재 문제**: 수동 검증만 기재
- **개선**: `kubectl` 기반 Smoke Test 스크립트 블록 추가

### 5. Rollback 절차 — AWS Well-Architected

- **글로벌 표준**: 모든 운영 절차에 "실패 시 조치" 포함 (Operational Readiness Review)
- **현재 문제**: 실패 시나리오 미기재
- **개선**: 각 단계별 "⚠️ 실패 시" 조치 가이드 추가

### 6. Client Secret → Vault — HashiCorp Best Practice

- **글로벌 표준**: OIDC Client Secret은 Vault에 중앙 저장, 서비스에서 참조
- **현재 문제**: client_secret 수동 복사
- **개선**: Vault KV 경로에 저장 → 서비스 설정에서 Vault 참조 패턴 명시

---

## ✅ 작업 내역

- [x] **1.1** Quick Reference 테이블 — 전체 초기 credential 조회 명령어 상단 집중 배치
- [x] **1.2** First-Login Force Change 절차 추가
- [x] **1.3** Secret Rotation 정책 섹션 추가
- [x] **1.4** Smoke Test 스크립트 블록 추가
- [x] **1.5** 각 단계별 "실패 시 조치" 추가
- [x] **1.6** Keycloak Client Secret → Vault 패턴 명시

---

## 🔗 관련 문서

- [post-deployment-operations-guide.md](../guides/post-deployment-operations-guide.md)
- [v06-advancement-strategy.md](../architecture/v06-advancement-strategy.md)
- [00-csp-independence-todo.md](../architecture/00-csp-independence-todo.md)
