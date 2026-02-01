# Jira Ticket: OPS-202 - Intelligent Stack Status Dashboard (make status)

## Summary
인프라 운영 효율성 증대 및 장애 대응 자동화를 위한 '지능형 상태 점검(make status)' 명령어를 구현하고 운영 SOP에 통합합니다.

## Description
기존의 파편화된 `kubectl` 명령어와 Terraform 출력을 통합하여, 운영자가 단일 명령어로 클러스터의 건강 상태를 진단하고 즉각적인 조치 방법을 안내받을 수 있는 인터페이스를 제공합니다.

### 핵심 기능
1.  **통합 대시보드**: ArgoCD 배포 현황, 시스템 포드 상태, Ingress 접속 정보를 한눈에 요약.
2.  **자동 터널링**: Kubernetes 접속에 필요한 SSM 터널이 없을 경우 자동으로 감지하여 실행.
3.  **지능형 장애 진단 (Operational Intelligence)**:
    *   **Stuck Namespace**: Finalizer로 인해 삭제가 멈춘 네임스페이스 탐색 및 해결 명령어 제시.
    *   **Stuck Application**: ArgoCD 앱 삭제가 멈춘 경우 강제 정리 명령어 제시.
    *   **Unknown Sync**: ArgoCD 내부 통신 장애 상황 인지 및 가이드 제시.
4.  **한글화 지원**: 한국어 헤더 및 상황별 해석 가이드 제공.

## Acceptance Criteria
- [x] `make status ENV=... STACK=...` 명령어로 실행 가능해야 함.
- [x] 부트스트랩 스택(55-bootstrap)에 특화된 K8s 진단 로직 포함.
- [x] 장애 감지 시 "Required Actions" 섹션에 실제 실행 가능한 `kubectl` 조치 명령어가 출력되어야 함.
- [x] 운영 가이드(`docs/runbooks/gitops-management.md`)에 반영 완료.

---

## 작업 이력 및 커밋 가이드 (Commit History)

작업의 원자성을 유지하기 위해 다음과 같은 커밋 단위를 권장합니다.

### 1. [Feat] Core status check script and Makefile integration
- **커밋 메시지**: `feat(ops): implement core check-status.sh and makefile integration`
- **내용**: `scripts/common/check-status.sh` 초기 버전 및 `Makefile` 타겟 추가.

### 2. [Refactor] Idempotent tunnel management
- **커밋 메시지**: `refactor(ops): reuse tunnel.sh for idempotent ssm tunnel management`
- **내용**: `check-status.sh` 내부의 터널 로직을 `scripts/common/tunnel.sh`로 위임.

### 3. [Feat] Intelligent diagnostics and Korean localization
- **커밋 메시지**: `feat(ops): add intelligent diagnostics for stuck resources and kr localization`
- **내용**: 네임스페이스/앱 고착 감지 로직, 필수 조치 안내, 한글화 반영.

### 4. [Docs] Update GitOps operation runbook
- **커밋 메시지**: `docs(ops): update gitops management guide with status-based SOP`
- **내용**: `docs/runbooks/gitops-management.md` 생성 및 업데이트.
