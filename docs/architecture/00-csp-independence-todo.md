# UnifiedMeta 아키텍처 — TODO List

> **기준 시점**: v0.6 아키텍처  
> **최종 업데이트**: 2026-02-12 (접근 제어 스택 전략 추가)  
> **원칙**: AWS 기반 현행 구현을 **완결성 있게 완료** 후, 확장/개선 착수

### 표기 규칙

| 표기 | 의미 |
|------|------|
| `- [ ]` | 미착수 |
| `- [/]` | 진행 중 |
| `- [x]` *(YYYY-MM-DD)* | 완료 (날짜 필수) |
| `- [-]` *(YYYY-MM-DD, 사유)* | 제외/보류 |

---

## 1. 솔루션 패키징 및 고객 납품

### AIPP Helm Chart (Tier 3)

- [ ] `charts/aipp/Chart.yaml` 작성
- [ ] `values.yaml` — 최소 구성 (외부 의존 없이 즉시 구동)
- [ ] `values-full.yaml` — Vault + Longhorn + cert-manager 통합
- [ ] pgvector / redis / rabbitmq StatefulSet 템플릿
- [ ] backend / frontend / linker Deployment 템플릿
- [ ] GPU 조건부 배포 (`linker.enabled`)
- [ ] Ingress 템플릿
- [ ] README.md 설치 가이드

### 패키징 매트릭스

- [ ] Tier 1 / 2 / 3 별 포함·제외 컴포넌트 정의서 작성
- [ ] Platform Bootstrap Script (Tier 2용)
- [ ] IaC Quickstart 문서 보강 (`make apply-all-auto` 기반 Tier 1)

---

## 2. AIPP 서비스 운영 안정화

### 이미지 관리

- [ ] GitLab Container Registry → Harbor 이미지 미러링 자동화
- [ ] Harbor CI 파이프라인 구축 (push → tag → sync)
- [ ] 이미지 취약점 스캔 정책 적용 (Trivy)

### GPU 노드 전략

- [ ] `enai-linker` GPU 노드 요구사항 문서화
- [ ] GPU 노드 on-demand 스케일링 설계 (Karpenter)
- [ ] GPU 미보유 환경용 fallback 배포 전략

### 서비스 모니터링

- [ ] AIPP 서비스별 SLO 정의 (Pod Restart, 5xx Rate, Latency P99)
- [ ] Grafana Alert Rule 체계화
- [ ] Alert → Runbook URL 연결

---

## 3. 운영 자동화

### Backup/DR

- [ ] Velero 스케줄 백업 구성 (`daily-backup: 0 2 * * *`)
- [ ] 백업 대상 네임스페이스 확정 (aipp, apps, vault)
- [ ] 복원 절차 검증 및 Runbook 작성

### CI/CD 고도화

- [ ] ArgoCD Image Updater 도입 (Harbor webhook 연동)
- [ ] Git push → Build → Harbor push → ArgoCD sync 파이프라인

### Secret 관리

- [ ] Vault Dynamic Secrets 도입 (DB creds auto-rotation)
- [ ] Vault Agent Sidecar 패턴 표준화

---

## 4. 개발/검증 환경

- [ ] k3d/kind 기반 로컬 미니 클러스터 구성
- [ ] `make verify` 타겟 추가 (kubectl health check 자동화)
- [ ] `stacks/staging/` 환경 추가 (dev 동일 구조, 축소 스펙)
- [ ] 비용 최적화: Karpenter/KEDA 기반 스케일링

---

## 5. CSP 독립성 확보

> **AWS 구현 완결 후** 착수. 상세 항목은 [v06-advancement-strategy.md](./v06-advancement-strategy.md) 참조.

### GitOps Values 분리 (설정 레이어)

- [ ] Nginx Ingress Controller — Service annotations 프로파일 분리
- [ ] Vault — Auto-Unseal seal stanza 분리
- [ ] Longhorn — Backup Target 분리
- [ ] cert-manager — DNS-01 Issuer 분리
- [ ] ExternalDNS — Provider 분리
- [ ] RKE2 Bootstrap — Userdata 추상화
- [ ] Teleport 대체 — 접근 제어 스택 전환 (→ 섹션 11 참조)

### Terraform Provider 분리 (인프라 레이어)

> **타깃 CSP 계약 확정 후** 착수. 사전 설계 문서화만 선행.

- [ ] CSP-specific vs Portable 모듈 경계 확정 문서
- [ ] `stacks/` 디렉토리 재구조화 설계 (aws / azure / common)
- [ ] L1~L2 모듈 CSP별 구현 (타깃 CSP 확정 시)
- [ ] `stacks/dev/` → `stacks/aws/dev/` 마이그레이션

### 전환 검증

- [ ] 타깃 CSP 환경 배포 테스트
- [ ] E2E 통합 검증 (`make verify`)
- [ ] CSP 전환 운영 가이드 (Runbook) 작성

---

## 6. 문서화 및 거버넌스

- [ ] 패키징 매트릭스 문서 (Tier별 포함/제외 정의)
- [ ] CSP 전환 가이드 (values 프로파일 사용법)
- [ ] 운영 Runbook 체계화 (Alert → 조치 절차)
- [ ] 아키텍처 변경 이력 관리 (ADR)

## 7. 보안 및 공급망 무결성 (Global Standard)

> CNCF Security TAG / NIST SP 800-190 / ISMS-P 기준 필수 항목

### K8s 보안 강화

- [ ] Pod Security Admission (PSA) — `baseline` → `restricted` 프로파일 적용
- [ ] RBAC 최소 권한 원칙 — ServiceAccount별 최소 Role 정의
- [ ] etcd 암호화 — Secrets at rest encryption 활성화
- [ ] Audit Logging — K8s API audit policy 구성 + 로그 수집

### 이미지 공급망

- [ ] 이미지 서명 (Cosign) — Harbor push 시 서명 자동화
- [ ] 서명 검증 (Kyverno/OPA) — 서명 안 된 이미지 배포 차단
- [ ] SBOM 생성 — 빌드 시 Software Bill of Materials 자동 생성

### 정책 관리 (Policy-as-Code)

- [ ] Kyverno 또는 OPA Gatekeeper 도입
- [ ] 필수 라벨 강제 (`app`, `version`, `owner`)
- [ ] 특권 컨테이너 차단 정책
- [ ] 외부 레지스트리 허용 목록 제한

---

## 8. 안정성 및 복원력 (Global Standard)

> CNCF Production Readiness / SRE Best Practices 기준

### 워크로드 보호

- [ ] PodDisruptionBudget (PDB) — 핵심 서비스 `minAvailable` 설정
- [ ] HorizontalPodAutoscaler (HPA) — CPU/메모리 기반 자동 스케일링
- [ ] Resource Quotas — 네임스페이스별 리소스 상한 설정
- [ ] LimitRange — Pod/Container 기본 리소스 제한 정의

### 배포 안정성

- [ ] TopologySpreadConstraints — AZ 간 Pod 분산 배치
- [ ] PriorityClass — 핵심 서비스 우선순위 정의 (system > platform > app)
- [ ] Rollout Strategy — Canary 또는 Blue/Green 배포 전략

### 장애 대응

- [ ] Liveness/Readiness/Startup Probe — 전 서비스 표준화
- [ ] Circuit Breaker 패턴 검토 (서비스 간 장애 전파 차단)
- [ ] 복원 훈련 — Velero 복원 시나리오 정기 실행

---

## 9. 관측성 성숙도 (Global Standard)

> OpenTelemetry / Google SRE Book 기준

### 분산 추적

- [ ] OpenTelemetry Collector 도입 (application-level instrumentation)
- [ ] Trace → Tempo, Metrics → Prometheus, Logs → Loki 파이프라인 통합
- [ ] TraceID ↔ LogID 상관관계 (Correlation) 설정

### 로깅 표준

- [ ] 구조화 로깅 (Structured Logging) 표준 정의 — JSON format
- [ ] 로그 레벨 표준화 (ERROR/WARN/INFO/DEBUG)
- [ ] 로그 보존 정책 — Hot (7일) / Warm (30일) / Cold (90일)

### SLI/SLO 프레임워크

- [ ] 서비스별 SLI 정의 (가용성, 지연시간, 에러율)
- [ ] SLO 목표 수치 확정 (예: 99.9% 가용성)
- [ ] Error Budget 모니터링 대시보드

---

## 10. 네트워크 및 트래픽 관리 (Global Standard)

> Zero-Trust Networking / CNCF Service Mesh 기준

### 네트워크 정책

- [ ] Cilium NetworkPolicy — 네임스페이스 간 트래픽 격리
- [ ] 기본 Deny-All → 명시적 Allow 정책 전환
- [ ] Egress 제한 — 외부 통신 허용 목록 관리

### 서비스 간 보안

- [ ] mTLS 검토 — 서비스 간 통신 암호화 (Cilium 또는 Service Mesh)
- [ ] API Rate Limiting — Ingress 레벨 요청 제한

### DNS 복원력

- [ ] CoreDNS 캐싱 최적화
- [ ] DNS failover 전략 (split-horizon 환경)

---

## 11. Zero-Trust 접근 제어 스택 (Teleport 대체)

> **배경**: Teleport CE는 AGPL-3.0 (소스), v16부터 상용 라이선스 (바이너리).  
> 상용 제품 패키징 시 수정/재판매 **불가**. 허용적 라이선스 대안 필수.  
> On-prem 고객 지원을 위해 CSP 네이티브 도구(SSM/IAP/Bastion) 의존 불가.

### 확정 방향

| 역할 | 현재 (Teleport) | 대안 | 라이선스 |
|------|:---:|:---:|:---:|
| SSO/IdP | Keycloak | **Keycloak** (유지) | Apache 2.0 |
| App Access (웹 UI 프록시) | Teleport App Access | **Pomerium** | Apache 2.0 |
| K8s kubectl | SSM → Bastion | **Rancher Shell** (이미 배포) | Apache 2.0 |
| VM/서버 리모트 접근 | SSM Session Manager | **ShellHub** (평가 중) | Apache 2.0 |
| 노드 OS 디버깅 | SSH | `kubectl debug node/` | K8s 내장 |

### App Access — Pomerium 도입

- [ ] Pomerium Helm Chart 배포 (K8s 내)
- [ ] Keycloak OIDC 연동 구성
- [ ] 서비스별 라우트 정책 정의 (ArgoCD, Grafana, Harbor, Longhorn, Rancher)
- [ ] 기존 Teleport App Access 서비스 마이그레이션
- [ ] TLS 인증서 연동 (cert-manager)

### VM 리모트 접근 — 후보 평가

> **리스크**: 오픈소스 라이선스 전환 추세 (NetBird BSD→AGPL, HashiCorp MPL→BSL)  
> ShellHub도 향후 AGPL 전환 가능성 있음. Apache 2.0 버전 fork 확보 대비 필요.

- [ ] ShellHub Community Edition PoC (에이전트 배포 + 웹 터미널 검증)
- [ ] MeshCentral PoC (K8s 배포 가능성 + 리소스 측정)
- [ ] 자체 경량 에이전트 Feasibility 검토 (Go + WebSocket + xterm.js)
- [ ] 후보 선정 및 아키텍처 확정

### 평가 기준

| 기준 | 필수/권장 |
|------|:--------:|
| Apache 2.0 / MIT / BSD 라이선스 | **필수** |
| 에이전트 기반 outbound (인바운드 포트 불필요) | **필수** |
| K8s Helm Chart 배포 지원 | **필수** |
| Keycloak OIDC SSO 연동 | 권장 (Pomerium 앞단으로 대체 가능) |
| Session Recording | 권장 (규제 환경용) |
| On-prem / CSP 무관 동일 동작 | **필수** |

### SSH-less Operations 전환

- [ ] `kubectl debug node/` 기반 노드 디버깅 절차 표준화
- [ ] Rancher Shell 접근 경로 문서화 (Pomerium 경유)
- [ ] Bastion SSH/SSM 의존 스크립트 정리 및 전환 계획
- [ ] Post-Deployment Guide 업데이트 (SSH-less 운영 모델 반영)

### CSP별 접근 전략 (상용 제품 관점)

| 환경 | VM 리모트 접근 | 비고 |
|------|:---:|------|
| AWS | ShellHub (통합) 또는 SSM (네이티브) | 고객 선택 |
| GCP | ShellHub (통합) 또는 IAP (네이티브) | 고객 선택 |
| Azure | ShellHub (통합) 또는 Bastion (네이티브) | 고객 선택 |
| **On-Prem** | **ShellHub (필수)** | CSP 도구 없음 |

---

## 12. 크리덴셜 관리 중앙화 (90-credential-init)

> **의존**: 55-bootstrap(Vault 서버) + 60~80(전체 서비스 배포 완료)  
> **참조**: [credential-bootstrap-strategy](../jira/2026-02-13-credential-bootstrap-strategy.md)

### ESO + Vault 연동

- [ ] ESO(External Secrets Operator) ArgoCD Application 정의
- [ ] ClusterSecretStore (Vault K8s Auth) 정의
- [ ] Vault K8s Auth Role + Policy 생성 (ESO용)

### 전 서비스 SSO 구성

- [ ] Keycloak OIDC Client 생성 (ArgoCD, Grafana, Harbor, Rancher)
- [ ] OIDC Client Secret → Vault KV 저장 (`vault-seed.sh`)
- [ ] ExternalSecret 정의 (서비스별 OIDC Secret 자동 동기화, 4개)
- [ ] ArgoCD OIDC 설정 (`argocd-cm`)
- [ ] Grafana `auth.generic_oauth` 설정
- [ ] Harbor OIDC Auth Mode 설정
- [ ] Rancher Keycloak Auth Provider 설정

### 초기 크리덴셜 Discovery

- [ ] `55-bootstrap/outputs.tf` — `platform_credentials` 통합 output
- [ ] `credentials.sh` — terraform output 우선 → kubectl fallback

### 운영 안정화

- [ ] break-glass 검증 (Keycloak 다운 시 로컬 admin 접근)
- [ ] 초기 K8s Secret 정리 (SSO 전환 완료 후)
- [ ] MFA 강제 활성화 (Keycloak Realm 설정)
- [ ] Post-Deployment Operations Guide 업데이트

---

## 착수 판단 기준

| 질문 | 답변이 "예"면 |
|------|-------------|
| AWS 기반 현행 구현이 완결되었는가? | 섹션 1~4 착수 |
| Helm Chart가 완성되었는가? | Tier 3 고객 납품 가능 |
| 섹션 1~4가 완료되었는가? | 섹션 5 착수 |
| 타깃 CSP 계약이 확정되었는가? | 섹션 5 Terraform 구현 착수 |
| 운영 환경이 안정화되었는가? | 섹션 7~10 단계적 적용 |
| 실 CSP 환경이 준비되었는가? | 섹션 5 전환 검증 착수 |
| **전체 서비스 배포가 완료되었는가?** | **섹션 12 (90-credential-init) 착수** |
