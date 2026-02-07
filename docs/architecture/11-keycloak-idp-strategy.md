# Keycloak 도입 전략 — 플랫폼 통합 IdP 아키텍처

**작성일**: 2026-02-07  
**상태**: 검토 중  
**관련**: NLB 아키텍처, ALBC 도입, Teleport 연동

---

## 1. 왜 Keycloak인가

Keycloak은 단순한 OIDC Provider가 아니라, **현재 플랫폼의 모든 인증 문제를 한 번에 해결하는 통합 IdP**입니다.

### 현재 문제들과 Keycloak이 해결하는 범위

| 현재 문제 | 현재 상태 | Keycloak 도입 후 |
|----------|----------|----------------|
| ALBC IRSA (Pod-level IAM) | ❌ RKE2에 OIDC 없음 | ✅ Keycloak이 OIDC Provider 역할 |
| 서비스별 개별 로그인 | ⚠️ 각 서비스 자체 인증 | ✅ **SSO** — 한 번 로그인으로 모든 서비스 |
| K8s API 접근 | 🔐 kubeconfig 토큰 | ✅ OIDC 기반 임시 토큰 |
| 사용자/권한 관리 | ⚠️ 서비스마다 분산 | ✅ **중앙 집중 관리** |
| 고객 멀티테넌트 | ❌ 미구현 | ✅ Realm 기반 테넌트 분리 |
| 감사 로그 | ⚠️ 서비스별 분산 | ✅ 통합 인증 이벤트 로그 |

### 네이티브 연동 가능한 현재 서비스 (검증 완료)

| 서비스 | 프로토콜 | 연동 방식 |
|--------|---------|----------|
| **Grafana** | OIDC | Generic OAuth → Keycloak Client |
| **ArgoCD** | OIDC | `argocd-cm` ConfigMap에 OIDC 설정 |
| **Rancher** | OIDC/SAML | UI에서 "Keycloak (OIDC)" 선택 |
| **Harbor** | OIDC | Admin → OIDC Auth Provider 설정 |
| **Teleport** | OIDC | `tctl`로 OIDC Connector 등록 |
| **K8s API** | OIDC | kube-apiserver `--oidc-issuer-url` 설정 |
| **AWS IAM** | OIDC Federation | IAM OIDC Provider로 등록 → IRSA |

---

## 2. 아키텍처 개요

```
                         ┌─────────────────────────────────┐
                         │         Keycloak (IdP)           │
                         │   keycloak.unifiedmeta.net       │
                         │                                  │
                         │  Realm: meta-platform            │
                         │  ├── Client: grafana             │
                         │  ├── Client: argocd              │
                         │  ├── Client: rancher             │
                         │  ├── Client: harbor              │
                         │  ├── Client: teleport            │
                         │  ├── Client: kubernetes          │
                         │  └── Client: aws-irsa            │
                         │                                  │
                         │  Users/Groups:                   │
                         │  ├── admin (platform-admin)      │
                         │  ├── dev   (developers)          │
                         │  └── ops   (operations)          │
                         └──────────┬──────────────────────┘
                                    │ OIDC
               ┌────────────────────┼────────────────────┐
               │                    │                    │
    ┌──────────▼─────┐   ┌────────▼───────┐   ┌───────▼────────┐
    │   K8s 서비스    │   │   AWS IAM      │   │   Teleport     │
    │ Grafana,ArgoCD  │   │ OIDC Provider  │   │ OIDC Connector │
    │ Rancher,Harbor  │   │ → IRSA         │   │ → SSO Login    │
    │ (SSO 로그인)    │   │ → ALBC Pod     │   │ → Role Mapping │
    └────────────────┘   └────────────────┘   └────────────────┘
```

### 인증 흐름

```
사용자 → Grafana 접속 → Keycloak 로그인 → OIDC 토큰 발급
                                           ↓
        → ArgoCD 접속 → 이미 로그인됨 (SSO) → 바로 접근
        → Rancher 접속 → 이미 로그인됨 (SSO) → 바로 접근
        → Teleport 접속 → 이미 로그인됨 (SSO) → 바로 접근
```

---

## 3. 배포 전략

### Option A: K8s 클러스터 내 배포 (Helm)

```
Keycloak Pod → PostgreSQL (60-postgres 재활용)
             → Ingress (Internal NLB 경유)
             → TLS (cert-manager)
```

- 장점: 기존 인프라 재활용, GitOps 관리
- 단점: K8s 의존 (클러스터 장애 시 인증 불가)

### Option B: 독립 EC2 배포 (권장)

```
Keycloak EC2 → PostgreSQL RDS 또는 기존 60-postgres
             → Internal ALB (Harbor 패턴과 동일)
             → ACM TLS
```

- 장점: K8s 독립, HA 구성 용이, 클러스터 재구축 시에도 인증 유지
- 단점: EC2 관리 추가

### 권장: Option B (독립 EC2)

Keycloak은 **인증의 근간**이므로, 인증 대상(K8s)에 의존하면 안 됩니다.
Harbor와 동일한 패턴(Golden Image + 독립 EC2 + Internal ALB)으로 배포가 글로벌 표준.

---

## 4. IRSA 연동 (ALBC 문제 근본 해결)

Keycloak 도입 시 ALBC의 OIDC 문제가 해결되는 구조:

```
1. Keycloak을 AWS IAM OIDC Provider로 등록
2. ALBC용 IAM Role 생성 (Trust Policy: Keycloak OIDC)
3. K8s ServiceAccount에 IAM Role ARN annotation
4. ALBC Pod → Keycloak 토큰 → AWS STS AssumeRoleWithWebIdentity → 임시 자격증명
5. ALBC가 NLB Target 자동 관리 (IP mode)
```

단, **비표준적 접근**: K8s 내부 ServiceAccount 토큰과 Keycloak 토큰은 다른 체계입니다.
IRSA는 K8s 자체 ServiceAccount 토큰(projected volume)을 사용하므로, **Keycloak과 IRSA는 직접 연동이 아닌 병렬 구성**이 정확합니다.

### 정확한 구조

```
Keycloak ──→ 사용자 인증 (SSO, K8s API, Teleport 등)
           ──→ AWS IAM OIDC Provider (사용자 레벨 AWS 접근)

K8s OIDC  ──→ Pod 인증 (IRSA) ← S3에 OIDC discovery 게시 필요
           ──→ ALBC, external-dns 등 Pod-level AWS 접근
```

> **결론**: Keycloak은 **사용자 인증**을 통합하고, **Pod IRSA**는 별도로 S3 OIDC endpoint를 구성해야 합니다. 두 개의 OIDC Provider가 각자 역할을 담당하는 것이 글로벌 표준입니다.

---

## 5. 단계별 도입 로드맵

| Phase | 내용 | 선행조건 |
|-------|------|---------|
| **Phase 0** | Keycloak EC2 배포 (Golden Image 기반) | 60-postgres 완료 |
| **Phase 1** | Grafana SSO 연동 (가장 단순) | Phase 0 |
| **Phase 2** | ArgoCD, Rancher SSO 연동 | Phase 1 검증 |
| **Phase 3** | Harbor OIDC 연동 | Phase 2 |
| **Phase 4** | Teleport OIDC Connector | Phase 3 |
| **Phase 5** | K8s API OIDC (kubectl 로그인) | Phase 4 |
| **Phase 6** | S3 OIDC endpoint → IRSA → ALBC | Phase 5 |

---

## 6. 스택 배치

```
현재:
  05-security → 10-golden-image → 15-access-control → ...
  → 50-rke2 → 55-bootstrap → 60-postgres → 61-neo4j → ...

추가:
  25-keycloak (독립 EC2 + Internal ALB)
  ├── Keycloak 서버 배포
  ├── PostgreSQL DB 연결 (60-postgres 또는 별도)
  └── DNS: keycloak.unifiedmeta.net (Private Zone)
```

> **번호 25**: Teleport(15) 이후, 기타 서비스 이전. K8s 의존 없이 독립 배포 가능한 위치.

---

## 7. EKS vs RKE2 관점에서의 의미

| 항목 | EKS | RKE2 + Keycloak |
|------|-----|----------------|
| 사용자 인증 | IAM Identity Center / Cognito | **Keycloak** |
| Pod IRSA | EKS OIDC (자동) | **S3 OIDC endpoint (수동)** |
| SSO | 없음 (서비스별) | **Keycloak SSO** ✅ |
| 멀티클라우드 | ❌ AWS 전용 | ✅ 어디서든 동일 |
| 테넌트 분리 | IAM Account 분리 | **Keycloak Realm** |

Keycloak 도입하면 **EKS보다 더 유연한 인증 아키텍처**를 가지게 됩니다.
EKS의 OIDC는 Pod IRSA 전용이고, 사용자 SSO는 별도 구축이 필요합니다.
