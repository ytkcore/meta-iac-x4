# 메타데이터 거버넌스 시장 플레이어 — 인프라 & 클라우드 기술 채택 현황

**작성일**: 2026-02-07  
**목적**: 주요 메타데이터/거버넌스 솔루션의 인프라 기술 스택 비교 분석

---

## 1. 전체 비교 매트릭스

| 솔루션 | 유형 | K8s 배포 | SSO/IdP | 시크릿 관리 | CSP | LB/네트워크 |
|--------|------|---------|---------|-----------|-----|-----------|
| **Atlan** | 상용 SaaS | EKS (vCluster 멀티테넌트) | **Keycloak** ★ | **HashiCorp Vault** ★ | AWS/Azure/GCP | Kong API GW |
| **Collibra** | 상용 SaaS | K8s (Docker) | SSO 지원 | **HashiCorp Vault** (Edge) | AWS/GCP | RESTful/GraphQL |
| **Alation** | 상용 SaaS | **EKS** | SAML SSO (Azure AD) | **HashiCorp Vault** + Azure KV | **AWS** (NLB, WAF, Route53) | AWS NLB |
| **DataHub** | 오픈소스 (LinkedIn) | Helm on K8s | **OIDC** (Okta, Keycloak) | K8s Secrets | AWS/GCP/Azure | — |
| **OpenMetadata** | 오픈소스 | Helm on K8s | **OIDC** | K8s Secrets → Vault (진행중) | AWS/GCP/Azure | — |
| **Apache Atlas** | 오픈소스 (Apache) | Helm on K8s | File/Kerberos | K8s Secrets | 자체 호스팅 | — |

---

## 2. 솔루션별 상세 분석

### 2.1 Atlan — 우리 아키텍처와 가장 유사 ★

| 항목 | Atlan 채택 기술 | 우리 계획 | 일치도 |
|------|---------------|----------|-------|
| 컨테이너 오케스트레이션 | EKS (vCluster 멀티테넌트) | RKE2 | ✅ K8s 기반 |
| IdP / SSO | **Apache Keycloak** | **Keycloak** | ✅✅ **동일** |
| 시크릿 관리 | **HashiCorp Vault** | **Vault** | ✅✅ **동일** |
| 정책 엔진 | Apache Ranger | — | — |
| API 게이트웨이 | Kong | nginx-ingress | ✅ 유사 |
| 워크플로우 | Argo Workflows | ArgoCD | ✅ Argo 생태계 |
| 검색/인덱싱 | Elasticsearch | OpenSearch | ✅ 동일 계열 |
| 그래프 DB | Apache Atlas (Metastore) | Neo4j | ✅ 그래프 기반 |
| 메시징 | Apache Kafka | — | — |
| DB | PostgreSQL + Cassandra | PostgreSQL | ✅ 동일 |

> **Atlan의 핵심 아키텍처 = Keycloak + Vault + K8s**  
> 이것은 우리가 도달하려는 목표 아키텍처와 **거의 동일**합니다.

### 2.2 Collibra

- **아키텍처**: 분산 마이크로서비스, Docker + K8s 오케스트레이션
- **클라우드**: AWS + GCP 멀티클라우드 SaaS
- **Vault 연동**: Collibra Edge에서 CyberArk/HashiCorp Vault 통합
  - 데이터소스 크리덴셜을 자체 저장하지 않고 Vault에서 Pull
  - 시크릿 로테이션 자동화
- **Metadata Graph**: 메타데이터 싱글 소스 오브 트루스
- **보안**: 암호화 + RBAC + 감사 로그

### 2.3 Alation

- **인프라**: AWS 기반 완전 관리형
  - **Amazon EKS** (컨테이너 오케스트레이션)
  - **AWS NLB** (네트워크 로드밸런서)
  - **AWS WAF** (웹 방화벽)
  - **Amazon Route 53** (DNS)
  - **Amazon RDS** (데이터베이스)
  - **Amazon S3** (스토리지)
  - **Amazon ECR** (컨테이너 레지스트리)
- **인증**: SAML SSO (Azure AD/Microsoft Entra ID)
- **Vault**: HashiCorp Vault 통합 (OCF 커넥터)
  - DB 패스워드, Kerberos 정보 등 Vault에서 관리
  - HCP/자체 Vault 모두 지원
  - **크리덴셜이 고객 VPC를 벗어나지 않음** (Alation Agent)
- **암호화**: 디스크 + 애플리케이션 레벨 이중 암호화
- **인증**: ISO 27001

> **ALation의 AWS 스택 = 우리의 현재 인프라와 매우 유사**  
> (EKS→RKE2, NLB, WAF, Route53, RDS→PostgreSQL, S3, ECR→Harbor)

### 2.4 DataHub (오픈소스, LinkedIn)

- **아키텍처**: 스키마 퍼스트 + 실시간 메타데이터 관리
  - GMS (Graph Metadata Service) + React Frontend
  - Kafka (이벤트 스트리밍) + Elasticsearch (검색)
  - MySQL/PostgreSQL/MariaDB + Neo4j (그래프)
- **K8s 배포**: 공식 Helm 차트 (v1.19+)
  - AWS EKS, GKE, AKS 가이드 제공
- **인증**: **OIDC SSO** 네이티브 지원
  - Okta, Google, **Keycloak** 연동 확인
  - JIT(Just-in-Time) 사용자 프로비저닝
  - OIDC 그룹 멤버십 자동 동기화
- **시크릿**: K8s Secrets (Vault 통합은 없음)

### 2.5 OpenMetadata (오픈소스)

- **K8s 배포**: 공식 Helm 차트 (EKS, GKE, AKS)
- **인증**: **OIDC** 네이티브 지원
  - `custom-oidc` 프로바이더 설정 가능
  - OIDC Client 크리덴셜 → K8s Secrets로 관리
  - 프로덕션: 자체 JWT 키페어 필수
- **시크릿**: K8s Secrets → **Vault 통합 진행 중** (GitHub Issue 활성)

---

## 3. 시장 기술 채택 트렌드 요약

### 인증/SSO

```
상용 (엔터프라이즈):  Keycloak (Atlan) / SAML (Alation, Collibra)
오픈소스:            OIDC 표준 (DataHub, OpenMetadata)

→ OIDC가 사실상 표준. Keycloak이 IdP로 가장 많이 채택됨.
```

### 시크릿 관리

```
상용:    HashiCorp Vault (Atlan, Collibra, Alation — 3사 모두 채택)
오픈소스: K8s Secrets → Vault 전환 중 (OpenMetadata)

→ Vault가 사실상 업계 표준. K8s Secrets만으로는 부족하다는 컨센서스.
```

### 인프라

```
컨테이너:  K8s 100% (전 솔루션)
CSP:      AWS 가장 많음, GCP/Azure 멀티클라우드 지원
배포:     Helm 차트 표준
```

---

## 4. 우리 아키텍처 포지셔닝

```
             시크릿 관리 성숙도
                ↑
   Vault       │  ★ Atlan     ★ Collibra
   기반        │                    ★ Alation
                │         ◆ 우리 (목표)
                │
   K8s         │  ○ DataHub    ○ OpenMetadata
   Secrets     │       ◇ 우리 (현재)
   기반        │  ○ Apache Atlas
                │
                └──────────────────────────→
                OIDC/SSO                 SAML/Kerberos
                  (현대적)                  (레거시)
```

### 핵심 인사이트

1. **Atlan이 Keycloak + Vault + K8s를 이미 채택** → 우리 아키텍처가 시장 최상위 플레이어와 동일 수준
2. **Vault는 상용 3사 모두 채택** → 오버스펙이 아니라 업계 표준
3. **OIDC SSO는 오픈소스도 기본** → Keycloak은 최소 요건
4. **Alation의 AWS 스택**은 우리의 현재 인프라와 놀랍도록 유사 (NLB, WAF, Route53, ECR)

> **결론**: Keycloak + Vault 도입은 "최신 트렌드 추종"이 아니라,  
> **시장 최상위 솔루션이 이미 검증한 아키텍처 패턴을 채택하는 것**입니다.
