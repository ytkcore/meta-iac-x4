# 플랫폼 아키텍처 고도화 — 최종 의사결정 문서

**작성일**: 2026-02-07 (Cilium 추가: 2026-02-08)  
**상태**: 최종 확정  
**범위**: 플랫폼 전체 Identity/Secrets/Access/Network 아키텍처 재설계

---

## 0. 의사결정 히스토리 — 본 문서에 이르기까지

본 문서는 한 번의 설계로 만들어진 것이 아니다.  
아래의 순차적인 기술 고민과 검토를 거쳐, **각 단계에서 부딪힌 질문에 대한 답을 쌓아가며** 최종 아키텍처에 도달했다.

### 의사결정 흐름

```
CCM 버그 → NLB 어떻게 고치지? → ALBC 도입 검토
  → ALBC IRSA가 필요한데 RKE2엔 OIDC가 없다 → OIDC를 어떻게 해결하지?
    → Keycloak이면 SSO도 되고 OIDC도 된다 → Keycloak 도입 결정
      → Workload ID는? SPIRE? → 현재는 Keycloak OIDC로 충분
        → 시크릿도 하드코딩인데? → Vault 도입 결정
          → 한 번에? 점진적으로? → 시장 검증 + 통합 재설계 결정
            → NLB IP-mode 왜 안 되지? → Pod IP가 overlay(10.42.x.x)라서 VPC unreachable
              → 근본 원인: Canal VXLAN overlay → Cilium ENI Mode로 전환 결정
```

### 각 문서가 다룬 질문과 결론

| # | 문서 | 다룬 질문 | 핵심 결론 |
|---|------|----------|----------|
| 1 | [08-nlb-architecture.md](08-nlb-architecture.md) | NLB Target이 왜 자동 등록이 안 되는가? | CCM의 Instance Mode가 원인, **ALBC IP Mode로 전환 필요** |
| 2 | [11-keycloak-idp-strategy.md](11-keycloak-idp-strategy.md) | 6개 서비스 개별 인증을 어떻게 통합하는가? | **Keycloak OIDC SSO**가 유일한 현실적 선택 |
| 3 | [12-platform-identity-architecture.md](12-platform-identity-architecture.md) | 글로벌 표준 Identity Stack은 무엇인가? | **4-Layer Stack** (Keycloak + SPIRE + Vault + Teleport) |
| 4 | [13-access-gateway-architecture.md](13-access-gateway-architecture.md) | 접근 제어를 솔루션 독립적으로 설계할 수 있는가? | `service_endpoint` 인터페이스로 **솔루션 교체 가능** 설계 완료 |
| 5 | [14-future-roadmap.md](14-future-roadmap.md) | 전체 고도화를 어떤 순서로 진행하는가? | Phase 1~5 단계별 로드맵, **EKS 전환보다 RKE2 유지가 유리** |
| 6 | [platform-identity-architecture.md](platform-identity-architecture.md) | AWS 의존성을 어떻게 제거하는가? | **CSP 종속 3개 제거** (CCM, NLB annotations, Node IAM) |
| 7 | [platform-identity-bridge-strategy.md](platform-identity-bridge-strategy.md) | 한 번에 전환 vs 점진적 전환? | **Bridge 전략**: AWS 활용 + ESO/overlay 추상화 레이어 |
| 8 | [market-player-infrastructure-research.md](market-player-infrastructure-research.md) | 우리 아키텍처가 오버스펙인가? | **아니다.** Atlan(시장 선두)이 Keycloak + Vault + K8s로 동일 구성 |
| 9 | [17-cilium-cni-architecture.md](17-cilium-cni-architecture.md) | NLB IP-mode 실패의 근본 원인은? | **Canal overlay가 원인** → Cilium ENI Mode로 VPC-native 전환 |

### 핵심 전환점 — SPIRE를 왜 보류했는가

4-Layer Stack 원안(문서 #3)에서는 SPIRE가 L2(Workload ID)를 담당했다.  
그러나 검토 과정에서 **Keycloak이 OIDC Provider로서 Workload Identity도 겸용**할 수 있다는 결론에 도달했다.

```
원안:   Keycloak(L1:사람) + SPIRE(L2:Pod)   → 2개 시스템
최종:   Keycloak(L1:사람 + L2:Pod)           → 1개 시스템으로 통합
```

SPIRE가 유일하게 제공하는 것(mTLS, Attestation)은 **현재 플랫폼 규모에서 불필요**하다.  
서비스 메시 도입이나 마이크로서비스 50개 이상 운영 시점에 재검토한다.

### 본 문서의 위치

> 위 8개 문서의 고민과 검토를 바탕으로,  
> **"무엇을, 왜, 어떤 순서로 도입하는가"** 에 대한 **최종 의사결정**을 기록한다.

---

## 1. Executive Summary

메타데이터 관리 및 거버넌스 플랫폼의 인프라를 **글로벌 업계 표준 수준으로 고도화**한다.

| 결정 사항 | 내용 |
|----------|------|
| **CNI** | **Cilium ENI Mode** (Canal 교체 — VPC-native Pod IP, eBPF) |
| **IdP / SSO** | Keycloak 도입 (사용자 SSO + 워크로드 OIDC 겸용) |
| **Secrets** | HashiCorp Vault 도입 (동적 시크릿, 자동 회전) |
| **Access** | Teleport 유지 (이미 완성) |
| **SPIRE** | **추후 도입 검토** (서비스 메시/mTLS 필요 시점) |
| **접근 방식** | 통합 재설계 (3-Layer Stack) + **클러스터 재구축** |

---

## 2. 왜 지금 고도화해야 하는가

### 2.1 현재 아키텍처의 한계 — 냉정한 진단

| 영역 | 현재 상태 | 문제 | 심각도 |
|------|----------|------|--------|
| **인증** | 서비스별 개별 로그인 | 6개 서비스 × 개별 계정, 퇴사자 차단 누락 위험 | 🔴 |
| **시크릿** | K8s Secret 하드코딩 | 평문 저장, 회전 없음, 감사 불가 | 🔴 |
| **NLB Target** | CCM 수동 등록 | Worker 변경 시 서비스 중단, Teleport 접근 장애 반복 | 🔴 |
| **Pod 네트워킹** | Canal VXLAN overlay | Pod IP(10.42.x.x) VPC unreachable → NLB IP-mode 불가 | 🔴 |
| **NetworkPolicy** | Canal (L3-L4) | L7(HTTP path) 정책 불가, Keycloak Admin/OIDC 분리 불가 | 🟡 |
| **워크로드 ID** | Node IAM Role | Pod 전체가 동일 권한, Least Privilege 위반 | 🟡 |
| **네트워크 관측성** | 없음 | Pod 간 트래픽 흐름 파악 불가 | 🟡 |

> **거버넌스 플랫폼이면서 자체 인프라 거버넌스가 미비** — 이 모순을 해소해야 한다.

### 2.2 시장 검증 — 경쟁 솔루션은 이미 채택

| 솔루션 | IdP/SSO | Secrets | Access | 근거 |
|--------|---------|---------|--------|------|
| **Atlan** (시장 선두) | **Keycloak** ★ | **HashiCorp Vault** ★ | Kong API GW | 우리 목표와 동일 |
| **Collibra** | SSO | **HashiCorp Vault** | RESTful | Vault Edge 연동 |
| **Alation** | SAML (Azure AD) | **HashiCorp Vault** | AWS NLB + WAF | AWS 의존 |
| **DataHub** (오픈소스) | **OIDC** (Keycloak) | K8s Secrets | — | OIDC 표준 |
| **OpenMetadata** (오픈소스) | **OIDC** | → Vault 전환 중 | — | Vault 로드맵 |

> **상용 3사(Atlan, Collibra, Alation) 모두 Vault 채택. OIDC SSO는 오픈소스도 기본.**  
> **Atlan = Keycloak + Vault + K8s** — 우리의 목표 아키텍처와 사실상 동일.  
> 📎 상세: [market-player-infrastructure-research.md](market-player-infrastructure-research.md)

---

## 3. 기술 스택 변화 — 버전별 진화 과정

### 3.1 아키텍처 마일스톤 정의

| 버전 | 시기 | 마일스톤 | 핵심 형상 |
|------|------|---------|----------|
| **v0.1** | W1 (1/29~) | Foundation | VPC + Golden Image + Bastion + Harbor |
| **v0.2** | W2 (2/03~) | K8s Core | RKE2 클러스터 + ArgoCD Pure GitOps |
| **v0.3** | W3 (2/05~) | Services | DB 3종 분리 + Observability + Teleport App Access |
| **v0.4** | W4 (2/07~) | Zero-Trust Access | Dual NLB + Dual Ingress + cert-manager DNS-01 |
| **v0.5** | W5~ | Identity & Secrets | Keycloak SSO + Vault + ALBC |
| **v1.0** | W6~ | Network Evolution | **Cilium ENI Mode** + 클러스터 재구축 + K8s-native Keycloak |

### 3.2 영역별 버전 진화 매트릭스

| 영역 | v0.1 (Foundation) | v0.2 (K8s Core) | v0.3 (Services) | v0.4 (Zero-Trust) | TO-BE (Identity) | 변경 과정 | 변경 이유 | 비고 |
|------|-------------------|-----------------|------------------|--------------------|-------------------|-----------|----------|------|
| **네트워크** | VPC + Subnet + NAT + IGW | 동일 ✅ | VPC Endpoints 추가 | 동일 ✅ | 동일 ✅ | 동일 ✅ | W1 구축 후 안정 | 변경 불필요 |
| **CNI** | — | Canal (VXLAN) | 동일 | 동일 | 동일 | **Cilium ENI Mode** | overlay → VPC-native | 🆕 NLB/NetworkPolicy 근본 해결 |
| **보안 기반** | IAM Role + SG + SSH Key | SG 규칙 보강 | DB별 SG 추가 | WAF ACL 추가 | 동일 ✅ | 동일 ✅ | 서비스별 격리 | `05-security`, `20-waf` |
| **머신 이미지** | Packer Golden Image v1 | 동일 ✅ | 동일 ✅ | 동일 ✅ | 동일 ✅ | 동일 ✅ | 불변 이미지 원칙 | `10-golden-image` |
| **접근 제어** | Bastion (SSH) | 동일 | Teleport EC2 HA 추가 | Teleport App Access 완성 | 동일 ✅ | 동일 ✅ | Zero-Trust, 세션 녹화 | `15-access-control` |
| **컨테이너 레지스트리** | Harbor EC2 + S3 | 동일 ✅ | 동일 ✅ | 동일 ✅ | 동일 ✅ | 동일 ✅ | OCI 레지스트리 확보 | `40-harbor` |
| **K8s 엔진** | — | RKE2 v1.31 (CP2 + W4) | 동일 ✅ | 동일 ✅ | 동일 ✅ | **재구축 (Cilium)** | CSP 독립 K8s | `50-rke2` |
| **GitOps** | — | ArgoCD App-of-Apps | Pure GitOps (Infra Context) | 동일 ✅ | 동일 ✅ | 동일 ✅ | 부트스트랩 자동화 완성 | `55-bootstrap` |
| **NLB / 트래픽** | — | Public NLB + CCM | 동일 | **Dual NLB** (Pub+Int) | **ALBC IP mode** | ✅ 네이티브 동작 | CCM → Dual NLB → ALBC → Cilium | VPC-native로 근본 해결 |
| **Ingress** | — | nginx-ingress (단일) | 동일 | **Dual Ingress** (Pub+Int) | 동일 ✅ | 동일 ✅ | 내부 트래픽 분리 | ElectionID 충돌 해결 |
| **TLS 인증서** | — | — | cert-manager (HTTP-01) | cert-manager (**DNS-01**) | 동일 ✅ | 동일 ✅ | 폐쇄망 인증서 발급 | Route53 플러그인 |
| **DNS** | Route53 (수동) | external-dns (자동) | Split-Horizon (Pub+Priv) | 동일 ✅ | 동일 ✅ | 동일 ✅ | 내/외부 DNS 분리 | `04-dns-strategy` |
| **스토리지** | — | Longhorn | 동일 ✅ | 동일 ✅ | 동일 ✅ | 동일 ✅ | CSP 무관 분산 스토리지 | S3 백업 연동 |
| **데이터베이스** | — | — | PostgreSQL + Neo4j + OpenSearch (각 EC2) | 동일 ✅ | 동일 ✅ | 동일 ✅ | 독립 수명주기, 장애 격리 | `60/61/62` 개별 스택 |
| **모니터링** | — | — | Grafana + Prometheus (K8s) | 동일 ✅ | 동일 ✅ | **+ Hubble** | Longhorn PV + 네트워크 관측 | Cilium Hubble 추가 |
| **NetworkPolicy** | — | — | — | — | — | **CiliumNetworkPolicy L7** | L3-L4 → L7 (HTTP) | eBPF 기반 |
| **kube-proxy** | — | iptables | 동일 | 동일 | 동일 | **Cilium eBPF 대체** | O(n) → O(1) | 성능 향상 |
| **사용자 인증** | 없음 | 서비스별 개별 | 동일 | 동일 | **Keycloak SSO** | 동일 ✅ | 퇴사자 즉시 차단, MFA | `25-keycloak` |
| **워크로드 인증** | 없음 | Node IAM Role | 동일 | 동일 | **Keycloak OIDC** | 동일 ✅ | Pod별 Least Privilege | SPIRE 추후 검토 |
| **시크릿 관리** | 없음 | K8s Secret (하드코딩) | 동일 | 동일 | **Vault** | 동일 ✅ | 업계 표준, 감사 추적 | DB dynamic secrets |

### 3.3 버전별 형상 요약

```
v0.1 (Foundation):
  VPC ── Golden Image ── Bastion ── Harbor
  "인프라 뼈대 완성. K8s 없음."

v0.2 (K8s Core):
  VPC ── RKE2 (CP2+W4) ── ArgoCD ── Longhorn ── nginx-ingress
  "K8s 동작 + GitOps. 서비스는 아직 없음."

v0.3 (Services):
  + Teleport HA ── PostgreSQL ── Neo4j ── OpenSearch ── Grafana
  "서비스 전부 배포. 개별 인증, 시크릿 하드코딩."

v0.4 (Zero-Trust Access):
  + Dual NLB ── Dual Ingress ── DNS-01 ── WAF ── Teleport App Access
  "외부/내부 트래픽 분리, Zero-Trust 접근. 하지만 인증/시크릿은 미해결."

v0.5 (Identity & Secrets):
  + Keycloak (SSO + OIDC) ── Vault (동적 시크릿) ── ALBC (IP mode)
  "3-Layer Identity Stack 완성. 업계 표준 달성."

v1.0 (Network Evolution + Clean Rebuild):
  + Cilium ENI Mode ── eBPF kube-proxy ── Hubble ── CiliumNetworkPolicy
  + Keycloak K8s-native (Dual Ingress: Public OIDC + Internal Admin)
  "VPC-native Pod 네트워킹. NLB/ALBC 네이티브 동작. L7 NetworkPolicy. 클러스터 재구축."
```

### 3.4 각 버전의 미해결 문제 → 다음 버전이 해결

| 버전 | 해결한 것 | 남긴 숙제 |
|------|----------|----------|
| v0.1 | 인프라 기반 | K8s 없음, 배포 체계 없음 |
| v0.2 | K8s + GitOps | 서비스 미배포, 모니터링 없음 |
| v0.3 | 전체 서비스 배포 | 개별 인증, 하드코딩 시크릿, 단일 NLB |
| v0.4 | Zero-Trust 접근, 트래픽 분리 | **인증 분산, 시크릿 미관리, CCM 버그** |
| v0.5 | **인증 통합, 시크릿 자동화, NLB 자동화** | **Pod overlay 네트워킹, L3-L4 NetworkPolicy** |
| v1.0 | **VPC-native Pod IP, L7 NetworkPolicy, eBPF** | SPIRE (mTLS, 추후 검토) |

### 3.5 Identity Stack 구조 변화 (v0.4 → TO-BE)

```
v0.4 (현재):                           TO-BE (고도화):

  [접근] Teleport ── SSH/App             [접근] Teleport ── SSH/App/DB/K8s
  [인증] 서비스별 개별                    [인증] Keycloak ── SSO + Workload OIDC
  [시크릿] K8s Secret (평문)             [시크릿] Vault ── 동적 생성/회전/감사
  [워크로드] Node IAM (AWS 전용)         [워크로드] Keycloak OIDC (CSP 범용)
```

### 3.6 아키텍처 다이어그램 (TO-BE)

```
┌──────────────────────────────────────────────────────────────────┐
│                    3-Layer Identity Stack                         │
│                                                                  │
│  ┌──────────────────┐  ┌──────────────┐  ┌────────────────────┐ │
│  │    Keycloak       │  │    Vault      │  │     Teleport       │ │
│  │   L1: Human SSO   │  │  L2: Secrets  │  │   L3: Access       │ │
│  │   L1+: Workload   │  │              │  │                    │ │
│  │      OIDC         │  │ 동적 시크릿   │  │   SSH, K8s, DB     │ │
│  │                   │  │ 자동 회전     │  │   Web App          │ │
│  │   5개 서비스 SSO  │  │ 감사 로그     │  │   세션 녹화        │ │
│  │   K8s OIDC Auth   │  │ PKI          │  │                    │ │
│  │   AWS/GCP/Azure   │  │              │  │                    │ │
│  │   WI Federation   │  │              │  │                    │ │
│  └────────┬─────────┘  └──────┬───────┘  └────────┬───────────┘ │
│           │                   │                    │             │
│           ▼                   ▼                    ▼             │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Kubernetes Platform (RKE2)                  │   │
│  │                                                          │   │
│  │  Grafana · ArgoCD · Rancher · Harbor · Longhorn          │   │
│  │  cert-manager · external-dns · ALBC · nginx-ingress      │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│              ┌───────────────┼───────────────┐                   │
│              ▼               ▼               ▼                   │
│           AWS API        GCP API         온프렘                  │
│       (Keycloak JWT    (Keycloak JWT   (Keycloak JWT            │
│        → STS)           → WIF)          → 직접 인증)            │
└──────────────────────────────────────────────────────────────────┘
```

---

## 4. 4-Layer → 3-Layer 조정: SPIRE 도입 보류 근거

### 4.1 왜 SPIRE를 지금 도입하지 않는가

[12-platform-identity-architecture.md](12-platform-identity-architecture.md)에서 정의한 4-Layer Stack 원안 대비, **L2(SPIRE)를 Keycloak이 흡수**하는 3-Layer로 조정한다.

| SPIRE 기능 | Keycloak 대체 | 현재 필요 여부 |
|-----------|-------------|-------------|
| Pod → CSP API 인증 (JWT) | ✅ Keycloak OIDC로 대체 | **필요** |
| Pod → 외부 서비스 인증 (JWT) | ✅ Keycloak OIDC로 대체 | **필요** |
| Pod 간 mTLS (X.509) | ❌ 불가 (SPIRE 고유) | 불필요 (서비스 메시 미사용) |
| Attestation (Pod 검증) | △ 제한적 | 불필요 (현재 규모) |

### 4.2 Keycloak = L1 + L2 겸용

```
Keycloak이 제공하는 것:
  사용자 SSO (L1 역할)     → OIDC/SAML, MFA, 그룹/역할 관리
  워크로드 OIDC (L2 역할)  → Service Account JWT → CSP STS/WIF

SPIRE만 제공할 수 있는 것:
  Pod 간 mTLS             → 인증서(X.509) 기반, 서비스 메시에서 필요
  Pod Attestation         → Node/클러스터 기반 Pod 신원 검증
```

### 4.3 SPIRE 도입 트리거 (아래 **하나 이상** 충족 시 검토)

1. **서비스 메시 도입** (Istio 등) → mTLS 필수
2. **마이크로서비스 50개 이상** → Pod 간 신원 증명 필수
3. **금융/의료 규제** → 인증서 기반 워크로드 인증 요구
4. **멀티클라우드 동시 운영** → SPIRE Federation 필요

> 현재: 인프라 관리 Pod 위주, 서비스 간 통신 최소 → **Keycloak OIDC로 충분**

---

## 5. 컴포넌트 간 연동 관계

```
사용자 인증 흐름:
  사용자 → Teleport → Keycloak (SSO) → JWT 발급 → 서비스 접근
  사용자 → Grafana → Keycloak (OIDC) → JWT 발급 → 대시보드 접근
  사용자 → kubectl → Keycloak (OIDC) → JWT 발급 → K8s API 접근

워크로드 인증 흐름:
  ALBC Pod → Keycloak (Client Credentials) → JWT 발급
           → AWS IAM (OIDC Provider = Keycloak)
           → STS AssumeRoleWithWebIdentity → 임시 자격증명
           → NLB/ALB Target Group 관리

시크릿 흐름:
  App Pod → Vault (K8s Auth / Keycloak OIDC) → 동적 DB 패스워드
  Vault → PostgreSQL → 임시 계정 자동 생성/만료
  Vault Audit → 누가 어떤 시크릿에 언제 접근했는지 자동 기록

접근 감사 흐름:
  모든 SSH/K8s/DB/Web 접근 → Teleport → 세션 녹화 + 감사 로그
```

---

## 6. Terraform 스택 변경

```
변경 없음:
  00-network → 05-security → 10-golden-image → 15-access-control → 20-waf
  → 30-bastion → 40-harbor → 50-rke2
  → 60-postgres → 61-neo4j → 62-opensearch
  → 70-observability → 80-access-gateway

변경:
  25-keycloak (신규)     ← Keycloak EC2 + Internal ALB + DNS
  55-bootstrap (변경)    ← ALBC Helm App 추가
                         ← Vault Helm App 추가 (또는 별도 EC2)
                         ← Keycloak OIDC → AWS IAM Provider 구성
```

| 컴포넌트 | 배포 형태 | 이유 |
|----------|----------|------|
| **Keycloak** | EC2 (Terraform `25-keycloak`) | DB 의존, 상태 유지, 독립 관리 |
| **Vault** | K8s Helm (ArgoCD App) 또는 EC2 | HA 필요 시 EC2, 단일은 K8s |
| **ALBC** | K8s Helm (ArgoCD App) | 표준 배포 방식, CCM 대체 |

### 6.1 환경별 LB 전략 (고객 납품 대응)

K8s 설계 자체가 Cloud Provider를 **교체 가능한 플러그인**으로 취급한다.  
이에 따라 배포 환경별 LB 컴포넌트만 교체하고, 나머지(nginx-ingress, Keycloak, Vault 등)는 동일하게 유지한다.

| 배포 환경 | LB 컴포넌트 | 배포 방식 | 비고 |
|----------|-----------|----------|------|
| **AWS** | ALBC (AWS Load Balancer Controller) | ArgoCD App | NLB IP mode 자동 Target |
| **GCP** | GCE Ingress Controller | ArgoCD App | GCP LB 자동 관리 |
| **Azure** | Azure Load Balancer Controller | ArgoCD App | Azure LB 자동 관리 |
| **온프렘 / 폐쇄망** | MetalLB 또는 Terraform LB | ArgoCD App 또는 IaC | L2/BGP 모드 |

```
교체 범위:  ArgoCD App yaml 1개 + nginx-ingress annotations 수정
유지 범위:  그 외 전체 (K8s 코어, Keycloak, Vault, Teleport, ArgoCD, Longhorn...)
```

> **글로벌 표준 사례**: Rancher/SUSE, Red Hat OpenShift, VMware Tanzu 모두 이 패턴 채택.  
> K8s의 Cloud Controller Manager 인터페이스 자체가 환경별 교체를 전제로 설계되어 있다.

---

## 7. 일정

| Phase | 작업 | 기간 |
|-------|------|------|
| **1** | ALBC + NLB IP mode (Teleport 안정화) | **D1-2** ✅ |
| **2** | Keycloak 배포 + 5개 서비스 SSO | **D3-7** ✅ |
| **3** | Keycloak → AWS IAM OIDC (Pod Identity) | **D8-9** ⏸️ Phase 6 이후 |
| **4** | Vault 배포 + Keycloak Auth + DB secrets | **D10-12** ✅ |
| **5** | CCM 제거 | — ⏸️ Phase 6에서 자연 해소 |
| **6** | **Cilium CNI + 클러스터 재구축 + Keycloak K8s** | **D14-16** 🆕 |

> Phase 1, 2, 4 완료. Phase 3, 5는 Phase 6(Cilium) 진행 시 자연 해소됨.

---

## 8. 리스크

| 리스크 | 확률 | 영향 | 대응 |
|--------|------|------|------|
| Keycloak → AWS IAM OIDC 연동 실패 | 낮음 | 높음 | Node IAM Role 폴백 유지 |
| Vault HA 구성 복잡도 | 중간 | 중간 | 초기 단일 노드 → 점진 확장 |
| 서비스별 OIDC 연동 이슈 | 중간 | 낮음 | Grafana 파일럿 → 나머지 순차 적용 |
| NLB 재생성 다운타임 | 확정 | 낮음 | 유지보수 윈도우 활용 |
| Cilium ENI Pod 밀도 제한 | 중간 | 중간 | Prefix Delegation (/28) 활성화 |
| VPC CIDR 소진 | 낮음 | 높음 | 서브넷 CIDR 사전 계산 |
| 클러스터 재구축 다운타임 | 확정 | 중간 | Blue-Green + DNS 전환 |
| 60-postgres 미배포 시 Keycloak 불가 | 확정 | 높음 | 60-postgres 선행 apply 필수 |

---

## 9. 최종 결정 요약

| 결정 | 선택 | 근거 |
|------|------|------|
| **CNI** | **Cilium ENI Mode** | VPC-native Pod IP, eBPF L7 NetworkPolicy, kube-proxy 대체, Hubble |
| IdP | **Keycloak** | OIDC 표준, 시장 선두 Atlan 채택, CSP 범용 |
| Secrets | **Vault** | 상용 3사 전원 채택, 동적 시크릿 업계 표준 |
| Access | **Teleport 유지** | 이미 완성, 추가 투자 불필요 |
| NLB | **ALBC IP mode** | Cilium ENI로 네이티브 동작 (overlay 없이) |
| Workload ID | **Keycloak OIDC** (SPIRE 아님) | 이중 역할로 컴포넌트 절약, 현재 규모 적합 |
| SPIRE | **추후 검토** | mTLS/서비스 메시 필요 시점에 도입 |
| K8s 엔진 | **RKE2 유지 + 재구축** | CSP 독립, Cilium CNI 포함 Clean Rebuild |

---

## 10. 참고 문서

- [12-platform-identity-architecture.md](12-platform-identity-architecture.md) — 4-Layer Stack 원안 (SPIRE 포함)
- [13-access-gateway-architecture.md](13-access-gateway-architecture.md) — Access Gateway 설계
- [14-future-roadmap.md](14-future-roadmap.md) — 전체 고도화 로드맵
- [17-cilium-cni-architecture.md](17-cilium-cni-architecture.md) — Cilium CNI 전환 상세 아키텍처
- [market-player-infrastructure-research.md](market-player-infrastructure-research.md) — 시장 플레이어 인프라 분석
- [platform-identity-bridge-strategy.md](platform-identity-bridge-strategy.md) — Bridge 전략 (참고용)
