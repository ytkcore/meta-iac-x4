# Platform Evolution Roadmap — 고도화 로드맵

**작성일**: 2026-02-07  
**상태**: 리서치 & 계획 단계  
**목적**: 현재 플랫폼 상태에서 목표 아키텍처까지의 진화 경로 정의

---

## 1. 현재 플랫폼 현황 (As-Is)

### 인프라 스택 구조 (2026-02 기준)

```
00-network          → VPC, Subnet, IGW, NAT, Route Table, VPC Endpoints
05-security         → IAM Role, Security Groups, SSH Key
10-golden-image     → Packer AMI (Docker, SSM Agent, AWS CLI, Teleport)
15-access-control   → Teleport EC2 HA (2AZ), Public ALB
20-waf              → AWS WAF ACL (Teleport ALB 보호)
30-bastion          → Bastion EC2 (Golden Image 기반)
40-harbor           → Harbor EC2 + Internal ALB + S3 Backend
50-rke2             → RKE2 Cluster (CP 2 + Worker 4, Canal CNI, External CCM)
55-bootstrap        → ArgoCD + App-of-Apps + Infra Context
60-postgres         → PostgreSQL EC2 (Standalone)
61-neo4j            → Neo4j EC2 (Standalone)
62-opensearch       → OpenSearch EC2 (Standalone)
70-observability    → Grafana + Prometheus (K8s)
80-access-gateway   → Teleport App Access (서비스 등록)
```

### 현재 아키텍처 특성

| 영역 | 현재 상태 | 성숙도 |
|------|----------|--------|
| **인프라** | Terraform IaC + Golden Image 패턴 | ✅ 완성 |
| **배포** | Pure GitOps (ArgoCD App-of-Apps + Infra Context) | ✅ 완성 |
| **트래픽** | Dual NLB (Public/Internal) + nginx-ingress | ⚠️ 수동 TG |
| **DNS** | Split-Horizon (ExternalDNS Public/Private) | ✅ 완성 |
| **TLS** | Hybrid (ACM 외부 + cert-manager 내부) | ✅ 완성 |
| **접근 제어** | Teleport SSH/App Access + WAF | ✅ 완성 |
| **인증** | 서비스별 개별 인증 | ❌ 분산 |
| **시크릿** | K8s Secret (하드코딩) | ❌ 미관리 |
| **워크로드 ID** | Node IAM Role (AWS 전용) | ⚠️ 제한적 |

---

## 2. 목표 아키텍처 (To-Be)

### 4-Layer Zero-Trust Identity Fabric

```
Layer 4: Access Proxy  ──→ Teleport (사내) / Guacamole (납품)
         "어떻게 접근하는가" — 세션 녹화, 감사, 접근 정책

Layer 3: Secrets Mgmt  ──→ Vault
         "비밀은 어디에 보관하는가" — 동적 시크릿, 자동 회전, PKI

Layer 2: Workload ID   ──→ SPIFFE/SPIRE
         "이 Pod은 누구인가" — X.509/JWT, mTLS, CSP Federation

Layer 1: Human ID      ──→ Keycloak
         "이 사람은 누구인가" — SSO, MFA, RBAC, OIDC
```

---

## 3. 단계별 고도화 로드맵

### Phase 1: ALBC 도입 — NLB Target 자동화 (단기)

**상태**: 설계 완료, 구현 대기

| 항목 | AS-IS | TO-BE |
|------|-------|-------|
| Target 유형 | Instance (Worker:NodePort) | **IP (Pod 직접)** |
| Target 등록 | 수동 ⚠️ | **자동** |
| 경로 | NLB → Worker → kube-proxy → Pod (2-hop) | NLB → **Pod** (1-hop) |
| Worker 추가 | 수동 TG 업데이트 | **자동** |

**선행조건**: RKE2 OIDC Provider 수동 구성, IAM IRSA Role

> 📎 상세: [08-nlb-architecture.md](08-nlb-architecture.md) / [ALBC Jira](../jira/2026-02-07-albc-adoption.md)

---

### Phase 2: Keycloak 도입 — 통합 SSO (중기)

**상태**: 리서치 완료, 설계 확정

신규 스택 `25-keycloak`을 추가하여 독립 EC2로 배포.

```
연동 대상: Grafana → ArgoCD → Rancher → Harbor → Teleport → K8s API
효과: 서비스별 개별 로그인 → 한 번 로그인으로 전부 접근 (SSO)
```

| 서비스 | 연동 프로토콜 | 난이도 |
|--------|-------------|--------|
| Grafana | OIDC (Generic OAuth) | 쉬움 |
| ArgoCD | OIDC (argocd-cm) | 쉬움 |
| Rancher | OIDC (UI 설정) | 쉬움 |
| Harbor | OIDC (Admin UI) | 중간 |
| Teleport | OIDC Connector | 중간 |
| K8s API | --oidc-issuer-url | 중간 |

> 📎 상세: [11-keycloak-idp-strategy.md](11-keycloak-idp-strategy.md)

---

### Phase 3: Vault 도입 — 동적 시크릿 관리 (중기)

**상태**: 리서치 단계

| 항목 | AS-IS | TO-BE |
|------|-------|-------|
| DB 패스워드 | K8s Secret (하드코딩) | Vault Dynamic Secrets (자동 생성/회전) |
| TLS 인증서 | cert-manager (Self-Signed) | Vault PKI (대체 가능) |
| AWS 자격증명 | Node IAM Role | Vault AWS Engine (임시 자격증명) |
| 감사 | 없음 | Vault Audit Log (누가 어떤 시크릿에 접근) |

**배포 옵션**: K8s 내 Helm 배포 또는 독립 EC2

---

### Phase 4: SPIFFE/SPIRE 도입 — 워크로드 ID (장기)

**상태**: 리서치 단계

```
현재: Node IAM Role (AWS 전용, Node 단위)
목표: SPIRE SVID (CSP 무관, Pod 단위)

효과:
  Pod → SPIRE SVID → AWS STS (AssumeRoleWithWebIdentity)
  Pod → SPIRE SVID → Vault 인증 (Vault 1.21+ SPIFFE Auth)
  Pod → SPIRE SVID → Pod 간 mTLS (서비스 메시 없이)
  Pod → SPIRE JWT  → GCP WIF / Azure WI Federation
```

> **핵심**: 코드 변경 없이 CSP 전환/추가 가능한 멀티클라우드 기반

---

### Phase 5: 납품형 솔루션 패키징 (장기)

**상태**: 리서치 완료 (Apache Guacamole)

| 항목 | Teleport (사내) | Guacamole (납품) |
|------|----------------|------------------|
| 라이선스 | AGPLv3 | **Apache 2.0** (납품 안전) |
| Windows RDP | Enterprise 전용 | **네이티브 지원** |
| 세션 녹화 | ✅ | ✅ |
| 배포 방식 | EC2 + SSM | **Docker Compose Appliance** |
| 브랜딩 | 어려움 | **Extension 시스템** (White-label) |
| ISMS-P | ✅ | ✅ |

**전략**: 80-access-gateway 스택의 `access_solution` 변수로 Teleport/Guacamole 자동 전환.

> 📎 상세: [Apache Guacamole 리서치](../research/apache_guacamole_adoption_review.md)

---

## 4. 비용-효과 분석

| 컴포넌트 | 추가 인프라 | 운영 난이도 | 비즈니스 가치 |
|----------|-----------|-----------|-------------|
| ALBC | 없음 (K8s Pod) | 낮음 | ★★★★☆ NLB 자동화, 수동 운영 제거 |
| Keycloak | EC2 1대 + DB | 중간 | ★★★★★ SSO 체감 효과 극대 |
| Vault | EC2 1~3대 | 높음 | ★★★★☆ 시크릿 보안 근본 해결 |
| SPIRE | 없음 (DaemonSet) | 중간~높음 | ★★★★★ 멀티클라우드 핵심 |
| Guacamole | Docker 1대 | 낮음 | ★★★★★ 납품 라이선스 해결 |

---

## 5. EKS 전환 vs RKE2 유지 판단

| 기준 | EKS | RKE2 + 4-Layer Stack |
|------|-----|----------------------|
| 초기 구축 속도 | ★★★★★ | ★★★☆☆ |
| AWS 종속도 | ★★★★★ (완전 종속) | ★☆☆☆☆ (CSP 독립) |
| 멀티클라우드 이관 | 재구축 필요 | **코드 변경 없음** |
| 온프렘 배포 | 불가 | **가능** |
| 고객 납품 유연성 | AWS 고객만 | **모든 고객** |
| 운영 부담 | 낮음 | 높음 (학습 투자) |

> **결론**: 고객 납품/멀티클라우드/온프렘이 목표라면 **RKE2 + 4-Layer Stack이 정답**.
> AWS 전용이라면 EKS가 압도적으로 효율적.

---

## 6. 참고 자료

- [12-platform-identity-architecture.md](12-platform-identity-architecture.md) — 4-Layer Identity Stack 상세
- [11-keycloak-idp-strategy.md](11-keycloak-idp-strategy.md) — Keycloak 도입 전략
- [08-nlb-architecture.md](08-nlb-architecture.md) — NLB/ALBC 아키텍처
- [13-access-gateway-architecture.md](13-access-gateway-architecture.md) — Access Gateway 설계
- [Apache Guacamole 리서치](../research/apache_guacamole_adoption_review.md) — 납품형 대안 분석
