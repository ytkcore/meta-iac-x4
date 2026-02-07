# CSP-Agnostic RKE2 Platform — Identity Architecture & Timeline

**작성일**: 2026-02-07  
**목표**: RKE2 레벨에서 AWS 의존성 제거, 글로벌 표준 4-Layer Identity Stack 적용

---

## 1. 현재 AWS 의존성 인벤토리

### 제거 대상 (K8s Layer — CSP 종속)

| 컴포넌트 | 파일 | AWS 의존성 | 대체 솔루션 |
|----------|------|-----------|-----------|
| **CCM** | `aws-cloud-controller-manager.yaml` | NLB 생성, Node lifecycle | **제거** — nginx-ingress가 직접 NLB 관리 불필요 |
| **NLB annotations** | `nginx-ingress.yaml`, `nginx-ingress-internal.yaml` | `service.beta.kubernetes.io/aws-*` | **CSP별 overlay** (values per env) |
| **Node IAM Role** | `50-rke2` Terraform | Pod → AWS API 직접 호출 | **SPIFFE/SPIRE** |

### 유지 (Infra Layer — CSP 제공 인프라)

| 컴포넌트 | 이유 |
|----------|------|
| EC2 (컴퓨팅) | 인프라 레이어, CSP 전환 시 VM으로 대체 |
| NLB (로드밸런서) | Terraform이 관리, K8s와 분리 가능 |
| Route53 | external-dns가 추상화 (GCP Cloud DNS, Azure DNS 지원) |
| ACM | cert-manager가 대체 가능 (Let's Encrypt / 자체 CA) |

### 이미 CSP-Agnostic ✅

| 컴포넌트 | 상태 |
|----------|------|
| **Longhorn** (스토리지) | ✅ 어디서든 동작 |
| **cert-manager** (TLS) | ✅ DNS-01 플러그인 방식 |
| **external-dns** (DNS) | ✅ 멀티 프로바이더 지원 |
| **Teleport** (접근) | ✅ CSP 무관 |
| **ArgoCD** (GitOps) | ✅ CSP 무관 |
| **nginx-ingress** (Ingress) | ✅ CSP 무관 |

---

## 2. 4-Layer Identity Stack

```
L4  Teleport   ──→ 접근 프록시 + 감사       [이미 완료 ✅]
L3  Vault      ──→ 시크릿 동적 생성/회전     [신규]
L2  SPIRE      ──→ 워크로드 ID (Pod별)      [신규]
L1  Keycloak   ──→ 사용자 SSO/MFA           [신규]
```

---

## 3. 개발 일정 산정

### Phase 1: Keycloak (SSO 통합) — 5일

| 일차 | 작업 | 산출물 |
|------|------|--------|
| D1 | `25-keycloak` Terraform 스택 (EC2 + ALB) | EC2 + DNS 동작 |
| D2 | PostgreSQL DB 연결 + Realm/Client 초기 구성 | Keycloak UI 접근 |
| D3 | Grafana + ArgoCD OIDC 연동 | SSO 로그인 2개 서비스 |
| D4 | Rancher + Harbor OIDC 연동 | SSO 로그인 4개 서비스 |
| D5 | Teleport OIDC Connector + 통합 테스트 | **SSO 완성** |

### Phase 2: SPIFFE/SPIRE (Workload ID) — 5일

| 일차 | 작업 | 산출물 |
|------|------|--------|
| D6 | SPIRE Server/Agent Helm 배포 (ArgoCD) | SPIRE 동작 |
| D7 | K8s Attestor 설정 + SVID 발급 테스트 | Pod SVID 확인 |
| D8 | AWS STS Federation (SPIRE → AssumeRole) | Pod → AWS API |
| D9 | ALBC 배포 + SPIRE SVID 기반 인증 | NLB IP mode 자동화 |
| D10 | nginx-ingress annotation → CSP overlay | **CCM 제거 가능** |

### Phase 3: Vault (Secrets) — 4일

| 일차 | 작업 | 산출물 |
|------|------|--------|
| D11 | Vault Helm 배포 (HA, integrated storage) | Vault UI 접근 |
| D12 | SPIFFE Auth 백엔드 + K8s Auth 설정 | Pod → Vault 인증 |
| D13 | DB dynamic secrets (PostgreSQL) | 패스워드 자동 생성 |
| D14 | K8s Secrets → Vault 마이그레이션 + 테스트 | **시크릿 중앙화** |

### Phase 4: CCM 제거 + 통합 테스트 — 3일

| 일차 | 작업 | 산출물 |
|------|------|--------|
| D15 | CCM ArgoCD App 제거, NLB Terraform 관리 전환 | AWS 의존성 제거 |
| D16 | E2E 테스트 (전체 서비스 SSO, NLB, TLS) | 통합 검증 |
| D17 | 문서 + 운영 가이드 + Git 정리 | **완료** |

---

## 4. 총 일정

| 구분 | 기간 | 누적 |
|------|------|------|
| Phase 1: Keycloak | **5일** | 5일 |
| Phase 2: SPIRE + ALBC | **5일** | 10일 |
| Phase 3: Vault | **4일** | 14일 |
| Phase 4: 통합 + 정리 | **3일** | **17일** |

### 최대한 빠르게 (병렬 진행 시)

```
Week 1: Keycloak 배포 + SSO 연동 (Phase 1)
Week 2: SPIRE 배포 + ALBC + Vault 배포 (Phase 2+3 병렬)
Week 3: 통합 테스트 + CCM 제거 + 문서화 (Phase 4)
```

> **최소 3주 (15 working days)**, 리스크 버퍼 포함 **4주**

### 우선순위별 축소 옵션

| 옵션 | 범위 | 기간 | 즉시 효과 |
|------|------|------|----------|
| **MVP** | Keycloak + ALBC (Node IAM) | **1주** | SSO + NLB 자동화 |
| **Standard** | + SPIRE | **2주** | + CSP 무관 Pod ID |
| **Full** | + Vault + CCM 제거 | **3~4주** | 완전 CSP-Agnostic |

---

## 5. Terraform 스택 최종 배치

```
현재:
  00-network → 05-security → 10-golden-image → 15-access-control → 20-waf
  → 30-bastion → 40-harbor → 50-rke2 → 55-bootstrap
  → 60-postgres → 61-neo4j → 62-opensearch
  → 70-observability → 80-access-gateway

추가:
  25-keycloak (신규)     ← Keycloak EC2 + Internal ALB
  55-bootstrap 변경      ← SPIRE, Vault Helm apps 추가
                         ← ALBC 추가
                         ← CCM 제거
```

---

## 6. 리스크

| 리스크 | 영향 | 대응 |
|--------|------|------|
| SPIRE + AWS STS 연동 복잡도 | +2~3일 | 먼저 Node IAM으로 동작 확인 후 전환 |
| Keycloak DB 의존 (60-postgres) | 배포 순서 | 60-postgres 먼저 apply |
| CCM 제거 시 기존 NLB 재생성 | 다운타임 | Terraform import로 기존 NLB 보존 |
| 서비스별 OIDC 연동 이슈 | +1~2일 | Grafana부터 파일럿 |
