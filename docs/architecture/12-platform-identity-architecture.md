# Best-of-Best 플랫폼 Identity Architecture

**작성일**: 2026-02-07  
**목적**: 글로벌 표준 + 국내 레퍼런스 기반, 멀티클라우드/온프렘 대응 최적 아키텍처 결정

---

## 1. 글로벌 표준 분석 (CNCF 2025 Landscape)

### 4-Layer Identity Stack (2025 글로벌 컨센서스)

```
Layer 4: Access Proxy ──→ Teleport
         "어떻게 접근하는가" (SSH, K8s, DB, App)
         세션 녹화, 감사, 접근 정책 적용

Layer 3: Secrets Mgmt ──→ Vault
         "비밀은 어디에 보관하는가"
         DB 패스워드, API 키, 인증서 동적 생성

Layer 2: Workload ID ──→ SPIFFE/SPIRE
         "이 Pod은 누구인가"
         X.509/JWT 기반 mTLS, CSP 연동

Layer 1: Human ID ──→ Keycloak
         "이 사람은 누구인가"
         SSO, MFA, RBAC, 그룹 관리
```

> **핵심**: 각 Layer는 겹치지 않으며, **하위 Layer가 상위 Layer의 인증 기반을 제공**.

### 2025년 주요 트렌드

| 트렌드 | 상세 |
|--------|------|
| Keycloak 26.4 | **SPIFFE SVID로 앱 인증 지원** (2025 신규) |
| Vault Enterprise 1.21 | **SPIFFE 인증 백엔드 추가** (2025 신규) |
| CNCF K8s 배포율 | 82% 프로덕션 사용 (2023 66% → 2025 82%) |
| Zero Trust | 업계 표준으로 정착, SPIFFE가 핵심 인에이블러 |
| IDP 채택률 | 23% → 27% (Q3 2024 → Q3 2025) |

---

## 2. 국내 주요 기업 레퍼런스

| 기업 | K8s 환경 | 인증 체계 | 특이사항 |
|------|---------|----------|---------|
| **토스** | 온프렘 K8s (2 DC, active-active) + Istio mesh | Netflix Passport 패턴 (자체 구현) | 게이트웨이에서 인증 토큰 전파, Calico CNI |
| **카카오** | DKOS (내부 KaaS) + 카카오클라우드 K8s Engine | 관리형 서비스에 통합 | EKS + IDC + 카카오클라우드 멀티클러스터 |
| **쿠팡** | 하이브리드 (온프렘 + AWS EKS) | AWS 네이티브 IAM | Aurora, DynamoDB, ElastiCache 기반 |
| **네이버** | NKS (네이버클라우드 K8s) | 관리형 서비스에 통합 | Terraform 기반 IaC |

### 국내 시사점

- **토스**: 자체 구현 — 규모가 충분할 때의 선택. Netflix Passport = 사실상 SPIFFE의 자체 구현
- **카카오**: 멀티클러스터 → Identity Federation 필수 (DKOS가 이 역할 수행)
- **쿠팡/네이버**: 관리형 CSP 의존 → CSP 전환 시 인증 전체 재구축 필요
- **SPIFFE 명시적 도입 사례**: 국내 공개 사례 없음 (2025 기준). 그러나 토스의 Passport 패턴이 사실상 동일 개념

---

## 3. Best-of-Best 아키텍처 결정

### 현재 플랫폼 현황 vs 목표

| 항목 | 현재 | 목표 (Best-of-Best) |
|------|------|-------------------|
| Human ID | 서비스별 개별 인증 | **Keycloak SSO** |
| Workload ID | Node IAM Role (AWS 전용) | **SPIFFE/SPIRE** (CSP 무관) |
| Secrets Mgmt | 없음 (하드코딩/K8s Secret) | **Vault** (동적 시크릿) |
| Access Proxy | Teleport (이미 도입) | **Teleport** (유지) ✅ |

### 최종 목표 아키텍처

```
┌──────────────────────────────────────────────────────────────────┐
│                    Zero-Trust Identity Fabric                    │
│                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────┐  ┌───────────┐ │
│  │  Keycloak    │  │   SPIRE     │  │  Vault   │  │ Teleport  │ │
│  │  (Human ID)  │  │ (Workload)  │  │ (Secret) │  │ (Access)  │ │
│  │             │  │             │  │          │  │           │ │
│  │ SSO/MFA     │  │ X.509/JWT   │  │ 동적 생성 │  │ 프록시    │ │
│  │ OIDC/SAML   │  │ mTLS        │  │ 자동 회전 │  │ 세션 녹화 │ │
│  │ 그룹/역할   │  │ CSP 연동    │  │ PKI       │  │ 감사 로그 │ │
│  └──────┬──────┘  └──────┬──────┘  └────┬─────┘  └─────┬─────┘ │
│         │                │              │               │       │
│         ▼                ▼              ▼               ▼       │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Kubernetes Platform (RKE2)                  │   │
│  │  ┌──────────────────────────────────────────────────┐    │   │
│  │  │ Services: Grafana, ArgoCD, Rancher, Harbor, Apps │    │   │
│  │  └──────────────────────────────────────────────────┘    │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│              ┌───────────────┼───────────────┐                   │
│              ▼               ▼               ▼                   │
│           AWS API        GCP API        온프렘 서비스             │
│         (SPIRE →         (SPIRE →       (SPIRE →                │
│          STS)             WIF)           mTLS)                   │
└──────────────────────────────────────────────────────────────────┘
```

### 컴포넌트 간 연동 관계

```
Keycloak ──OIDC──→ Teleport (사용자 SSO 로그인)
Keycloak ──OIDC──→ Grafana, ArgoCD, Rancher, Harbor (서비스 SSO)
Keycloak ──OIDC──→ K8s API Server (kubectl 인증)

SPIRE ──SVID──→ Vault (Pod이 Vault에 인증 — Vault 1.21+)
SPIRE ──SVID──→ AWS STS (Pod → AWS 서비스 접근)
SPIRE ──SVID──→ Pod 간 mTLS (서비스 메시 없이도 가능)
SPIRE ──JWT──→ 외부 CSP (GCP WIF, Azure WI Federation)

Vault ──동적 시크릿──→ DB 패스워드 (자동 생성/회전)
Vault ──PKI──→ 내부 TLS 인증서 (cert-manager 대안)
Vault ──Engine──→ AWS/GCP/Azure 임시 자격증명

Teleport ──프록시──→ SSH, K8s, DB, Web App (접근 + 감사)
```

---

## 4. 단계별 도입 로드맵 (현실적)

> **원칙**: 현재 동작하는 것을 깨뜨리지 않으면서 점진적으로 고도화

### Phase 0: 현재 (Already Done) ✅

```
Teleport → 접근 프록시 (SSH, App Access)
cert-manager → TLS 인증서
external-dns → DNS 관리
CCM + nginx-ingress → NLB 관리 (수동 Target)
```

### Phase 1: Keycloak (Human ID 통합) — 중기

```
신규: Keycloak EC2 배포 (25-keycloak 스택)
연동: Grafana → ArgoCD → Rancher → Harbor → Teleport SSO
효과: 서비스별 개별 로그인 → 한 번 로그인으로 전부 접근
```

### Phase 2: ALBC + Node IAM (워크로드 기본) — 단기

```
신규: ALBC 배포 (Node IAM Role 방식)
변경: nginx-ingress annotation → IP mode
효과: NLB Target 자동 관리, 수동 등록 제거
```

### Phase 3: Vault (Secrets 관리) — 중기

```
신규: Vault 배포 (K8s 또는 EC2)
변경: K8s Secrets → Vault Dynamic Secrets
연동: DB 패스워드 자동 생성/회전
효과: 하드코딩된 시크릿 제거, 감사 가능한 시크릿 접근
```

### Phase 4: SPIFFE/SPIRE (Workload ID) — 장기

```
신규: SPIRE Server/Agent DaemonSet 배포
변경: Node IAM Role → SPIRE SVID 기반 인증
연동: Vault SPIFFE Auth, AWS STS Federation
효과: Pod 단위 CSP 접근, mTLS, 멀티클라우드 준비
```

### Phase 5: 멀티클라우드 확장 — 장기

```
변경: SPIRE Federation (AWS ↔ GCP/온프렘)
효과: 코드 변경 없이 CSP 전환/추가 가능
```

---

## 5. 비용-효과 분석

| 컴포넌트 | 추가 인프라 | 운영 난이도 | 가치 |
|----------|-----------|-----------|------|
| Keycloak | EC2 1대 + RDS/PostgreSQL | 중간 | ★★★★★ SSO 체감 효과 극대 |
| ALBC | 없음 (K8s Pod) | 낮음 | ★★★★☆ NLB 자동화 |
| Vault | EC2 1~3대 | 높음 | ★★★★☆ 시크릿 보안 근본 해결 |
| SPIRE | 없음 (K8s DaemonSet) | 중간~높음 | ★★★★★ 멀티클라우드 핵심 |

---

## 6. EKS 전환 vs RKE2 유지 판단

| 기준 | EKS | RKE2 + 4-Layer Stack |
|------|-----|----------------------|
| 초기 구축 속도 | ★★★★★ (OIDC, IRSA 자동) | ★★★☆☆ (수동 구축) |
| AWS 종속도 | ★★★★★ (완전 종속) | ★☆☆☆☆ (CSP 독립) |
| 멀티클라우드 이관 | 재구축 필요 | **코드 변경 없음** |
| 온프렘 배포 | 불가 | **가능** |
| 아키텍처 깊이 | CSP 위임 (블랙박스) | 완전 이해/제어 |
| 고객 납품 유연성 | AWS 고객만 | **모든 고객** |
| 운영 부담 | 낮음 | 높음 (학습 투자) |

> **결론**: 고객 납품/멀티클라우드/온프렘이 목표라면 **RKE2 + 4-Layer Stack이 정답**.
> AWS 전용이라면 EKS가 압도적으로 효율적.
