# 신규 서비스를 위한 아키텍처 활용 팁

**작성일**: 2026-02-09  
**대상**: 본 플랫폼 위에서 신규 서비스를 개발·배포하는 팀  
**관련 문서**: [웹서비스 온보딩 가이드](web-service-onboarding.md), [Post-Deployment 운영 가이드](post-deployment-operations-guide.md)

> [!NOTE]
> 이 문서는 **배포 절차**가 아닌, **아키텍처 레벨에서 기반 서비스들을 잘 활용하기 위한 팁**을 정리합니다.
> 구체적인 배포 절차는 [웹서비스 온보딩 가이드](web-service-onboarding.md)를 참조하세요.

---

## 📋 목차

1. [플랫폼 전체 그림 — 한눈에 보기](#1-플랫폼-전체-그림--한눈에-보기)
2. [네이밍 — 혼란 없는 리소스 관리](#2-네이밍--혼란-없는-리소스-관리)
3. [GitOps — ArgoCD App 작성 팁](#3-gitops--argocd-app-작성-팁)
4. [Infra Context — 동적 인프라 값 안전하게 참조하기](#4-infra-context--동적-인프라-값-안전하게-참조하기)
5. [Ingress & TLS — 외부/내부 트래픽 분리 활용](#5-ingress--tls--외부내부-트래픽-분리-활용)
6. [DNS — 자동 등록 이해하기](#6-dns--자동-등록-이해하기)
7. [Keycloak SSO — 인증을 직접 만들지 마세요](#7-keycloak-sso--인증을-직접-만들지-마세요)
8. [Vault — 시크릿을 하드코딩하지 마세요](#8-vault--시크릿을-하드코딩하지-마세요)
9. [Access Gateway — 자동 서비스 등록](#9-access-gateway--자동-서비스-등록)
10. [Observability — 모니터링/로그/트레이스 연동](#10-observability--모니터링로그트레이스-연동)
11. [Cilium NetworkPolicy — L7 수준 접근 제어](#11-cilium-networkpolicy--l7-수준-접근-제어)
12. [스토리지 — Longhorn 활용 팁](#12-스토리지--longhorn-활용-팁)
13. [Harbor — 이미지/차트 레지스트리 활용](#13-harbor--이미지차트-레지스트리-활용)
14. [안티패턴 — 반드시 피해야 할 것들](#14-안티패턴--반드시-피해야-할-것들)
15. [신규 서비스 체크리스트](#15-신규-서비스-체크리스트)

---

## 1. 플랫폼 전체 그림 — 한눈에 보기

### 📖 용어 정리

| 용어 | 설명 |
|:---|:---|
| **Terraform** | HashiCorp의 IaC(Infrastructure as Code) 도구. HCL로 인프라를 선언적으로 정의하고 `plan` → `apply`로 프로비저닝 |
| **스택 (Stack)** | Terraform 코드의 논리적 단위. 본 플랫폼은 `00-network`부터 `80-access-gateway`까지 14개 스택으로 구성 |
| **프로비저닝 (Provisioning)** | 인프라 자원(VPC, EC2, K8s 등)을 생성하고 사용 가능한 상태로 준비하는 것 |
| **Golden Image (AMI)** | Docker, SSM Agent, Teleport Agent 등이 사전 설치된 불변(Immutable) EC2 이미지 |
| **IaC (Infrastructure as Code)** | 인프라를 코드로 관리하여 버전 관리, 재현성, 자동화를 보장하는 방법론 |

신규 서비스가 활용할 수 있는 기반 서비스들을 계층별로 정리하면:

```
┌─────────────────────────────────────────────────────────────────────┐
│  🔐 접근 제어 계층                                                   │
│  Teleport (SSH/K8s/DB/App), Keycloak (SSO/OIDC)                    │
├─────────────────────────────────────────────────────────────────────┤
│  📊 관측성 계층                                                      │
│  Prometheus (메트릭), Loki (로그), Tempo (트레이스), Grafana (시각화)  │
├─────────────────────────────────────────────────────────────────────┤
│  🚀 배포 계층                                                        │
│  ArgoCD (GitOps), Harbor (Registry), Longhorn (Storage)             │
├─────────────────────────────────────────────────────────────────────┤
│  🌐 네트워크 계층                                                     │
│  Dual NLB (Public/Internal), nginx-ingress (L7),                    │
│  Cilium (eBPF, VPC-native Pod IP), cert-manager (TLS)               │
├─────────────────────────────────────────────────────────────────────┤
│  🗄️ 데이터 계층                                                     │
│  PostgreSQL, Neo4j, OpenSearch                                      │
├─────────────────────────────────────────────────────────────────────┤
│  🏗️ 인프라 계층                                                     │
│  VPC, Subnets, Security Groups, Golden Image, IAM                   │
└─────────────────────────────────────────────────────────────────────┘
```

> [!TIP]
> 이 모든 계층이 **이미 프로비저닝되어 있습니다**.
> 신규 서비스는 직접 만들 필요 없이 **활용**만 하면 됩니다.

---

## 2. 네이밍 — 혼란 없는 리소스 관리

### 📖 용어 정리

| 용어 | 설명 |
|:---|:---|
| **SG (Security Group)** | AWS VPC의 가상 방화벽. 인바운드/아웃바운드 트래픽 규칙을 인스턴스 레벨에서 관리 |
| **TG (Target Group)** | ALB/NLB의 라우팅 대상 그룹. EC2 Instance 또는 Pod IP를 타겟으로 등록 |
| **ALB / NLB** | Application Load Balancer(L7) / Network Load Balancer(L4). 트래픽 분배용 AWS 관리형 서비스 |
| **워크로드 (Workload)** | 특정 업무를 수행하는 서비스 단위. 네이밍에서 서비스를 구분하는 핵심 식별자 |

### 네이밍 포맷

```
{env}-{project}-{workload}-{resource}-{suffix}
```

예시: `dev-meta-myapp-sg`, `dev-meta-myapp-tg-443`

### 핵심 규칙

| 구성 요소 | 설명 | 예시 |
|:---|:---|:---|
| `env` | 환경 | dev, stg, prod |
| `project` | 프로젝트명 | meta |
| `workload` | 서비스/워크로드 이름 | myapp, billing |
| `resource` | 리소스 종류 약어 | sg, ec2, tg |
| `suffix` | 추가 식별자 (선택) | 01, pub, 443 |

### 💡 팁

- AWS 콘솔에서 workload 이름으로 검색하면 **모든 관련 리소스가 한 번에** 조회됩니다.
- Kubernetes 리소스 이름도 동일한 패턴 유지를 권장합니다.
- 상세: [01-naming-convention.md](../architecture/01-naming-convention.md)

---

## 3. GitOps — ArgoCD App 작성 팁

### 📖 용어 정리

| 용어 | 설명 |
|:---|:---|
| **GitOps** | Git을 Single Source of Truth로 사용하여, Git push만으로 배포가 이뤄지는 운영 방법론 |
| **ArgoCD** | K8s용 GitOps 컨트롤러. Git 리포지토리의 매니페스트를 클러스터에 지속적으로 동기화 |
| **Application (CRD)** | ArgoCD가 관리하는 배포 단위. 하나의 Helm Chart 또는 매니페스트 디렉토리를 가리킴 |
| **Sync Wave** | ArgoCD의 배포 순서 제어 메커니즘. 숫자가 낮을수록 먼저 배포됨 |
| **Self-Heal** | 클러스터 상태가 Git과 달라지면 자동으로 Git 상태로 복구하는 기능 |
| **Prune** | Git에서 삭제된 리소스를 클러스터에서도 자동 삭제하는 기능 |
| **App-of-Apps** | Root Application이 하위 Application들을 관리하는 ArgoCD 패턴 |
| **Helm Chart** | K8s 리소스의 패키징 포맷. 템플릿 + values로 재사용 가능한 배포 단위 |
| **ServerSideApply** | K8s API 서버 측에서 리소스를 적용하는 방식. CRD 충돌 방지에 유리 |

### 올바른 배치 구조

```
gitops-apps/
├── bootstrap/           # 플랫폼 컴포넌트 (인프라팀 관리)
│   ├── cert-manager.yaml
│   ├── nginx-ingress.yaml
│   └── monitoring.yaml
├── platform/            # 플랫폼 레벨 앱 (인프라팀 관리)
│   └── rancher.yaml
└── apps/                # ✅ 신규 서비스는 여기에 배치
    └── my-web-service.yaml
```

> [!IMPORTANT]
> 신규 서비스 ArgoCD App은 반드시 **`gitops-apps/apps/`** 디렉토리에 생성하세요.
> `bootstrap/`은 플랫폼 컴포넌트 전용입니다.

### Sync Wave 가이드

```yaml
annotations:
  argocd.argoproj.io/sync-wave: "50"   # ← 신규 서비스 권장 Wave
```

| Wave 범위 | 용도 |
|:---:|:---|
| 0 ~ 10 | 인프라 기반 (cert-manager, CRDs) |
| 10 ~ 30 | 플랫폼 (Ingress, External-DNS, Monitoring) |
| 30 ~ 40 | 플랫폼 앱 (Rancher, Vault) |
| **50+** | **신규 서비스 (여기부터 사용)** |

### ArgoCD App YAML 최소 템플릿

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-service
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: apps          # 'apps' 레이블 사용
    app.kubernetes.io/managed-by: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "50"
spec:
  project: default
  source:
    repoURL: https://harbor.unifiedmeta.net/chartrepo/library  # Harbor 차트 사용 권장
    chart: my-service
    targetRevision: "1.0.0"
  destination:
    server: https://kubernetes.default.svc
    namespace: my-service                    # 서비스별 별도 NS 권장
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true                 # CRD 충돌 방지
```

### 💡 팁

- **`selfHeal: true`** 설정으로 누군가 수동 변경해도 Git 상태로 자동 복원됩니다.
- **`CreateNamespace=true`**이면 Namespace를 별도로 만들 필요 없습니다.
- **Helm Chart 소스**: Harbor OCI(`harbor.unifiedmeta.net`)를 우선 사용하세요. 폐쇄망 대비가 자동으로 됩니다.
- 상세: [09-bootstrap-strategy.md](../architecture/09-bootstrap-strategy.md), [10-gitops-role-division.md](../architecture/10-gitops-role-division.md)

---

## 4. Infra Context — 동적 인프라 값 안전하게 참조하기

### 📖 용어 정리

| 용어 | 설명 |
|:---|:---|
| **Infra Context** | Terraform이 생성한 동적 인프라 값(VPC ID, ACM ARN 등)을 K8s Secret에 담아 앱에 전달하는 본 플랫폼 고유 패턴 |
| **ARN (Amazon Resource Name)** | AWS 리소스의 고유 식별자. 예: `arn:aws:acm:ap-northeast-2:123456:certificate/abc-123` |
| **ACM (AWS Certificate Manager)** | AWS 관리형 TLS/SSL 인증서 서비스. NLB/ALB 단에서 HTTPS를 처리 |
| **K8s Secret** | Base64 인코딩된 민감 데이터를 저장하는 K8s 리소스. Pod에서 환경변수나 볼륨으로 참조 |
| **lookup 함수** | Helm 템플릿에서 클러스터 내 기존 리소스를 조회하는 함수 |

### 핵심 개념

Terraform이 생성한 동적 인프라 값(VPC ID, ACM ARN, 도메인 등)은 `infra-context` Secret에 담겨 있습니다.

```
kube-system/infra-context Secret
  ├── base_domain  = "unifiedmeta.net"
  ├── acm_arn      = "arn:aws:acm:..."
  ├── vpc_id       = "vpc-0abc..."
  ├── region       = "ap-northeast-2"
  └── ...
```

### Helm Chart에서 참조하는 방법

```yaml
# values.yaml 또는 ArgoCD Application에서
{{- $infraCtx := (lookup "v1" "Secret" "kube-system" "infra-context").data }}
domain: {{ index $infraCtx "base_domain" | b64dec }}
```

### 💡 팁

- 서비스 코드에 `unifiedmeta.net` 같은 **도메인을 하드코딩하지 마세요**. 환경(dev/stg/prod)마다 다릅니다.
- `infra-context`를 사용하면 동일 코드로 모든 환경에 배포할 수 있습니다.
- Git 매니페스트는 **정적(Static)** 으로 유지하고, 런타임에 동적 값을 주입하는 것이 원칙입니다.

> [!CAUTION]
> `infra-context` Secret은 **읽기 전용**입니다. Terraform 외에는 수정하면 안 됩니다.
> 수정이 필요하면 Terraform 코드를 변경하고 `make apply`를 실행하세요.

---

## 5. Ingress & TLS — 외부/내부 트래픽 분리 활용

### 📖 용어 정리

| 용어 | 설명 |
|:---|:---|
| **Ingress** | K8s에서 외부 HTTP(S) 트래픽을 클러스터 내부 Service로 라우팅하는 규칙 정의 |
| **IngressClass** | 어떤 Ingress Controller가 해당 Ingress를 처리할지 지정. 본 플랫폼은 `nginx`(Public)과 `nginx-internal` 두 가지 |
| **NLB (Network Load Balancer)** | AWS L4 로드밸런서. TCP/UDP 수준에서 트래픽을 분배. 본 플랫폼은 Public/Internal 2개 운영 |
| **North-South Traffic** | 클러스터 외부↔내부 간 트래픽 (사용자 요청). NLB → Ingress → Pod 경로 |
| **East-West Traffic** | 클러스터 내부 Pod↔Pod 간 트래픽. NLB를 거치지 않음 |
| **TLS Termination (SSL Offloading)** | 암호화된 HTTPS 연결을 LB 또는 Ingress에서 복호화하여 백엔드에는 HTTP로 전달 |
| **cert-manager** | K8s에서 TLS 인증서를 자동 발급/갱신하는 컨트롤러. Let's Encrypt 연동 |
| **DNS-01 Challenge** | 도메인 소유를 DNS TXT 레코드로 증명하는 TLS 인증서 발급 방식. Hairpin 문제 없음 |
| **HTTP-01 Challenge** | 도메인 소유를 HTTP 요청으로 증명하는 방식. 본 플랫폼에서는 hairpin 문제로 **사용 금지** |
| **Hairpin Routing** | Pod이 자신의 외부 주소(Ingress)로 요청을 보낼 때 NAT 루프가 발생하는 문제 |
| **Split-Horizon** | 같은 도메인이 접근 위치에 따라 다른 IP를 반환하는 DNS 구성. Public/Private Zone 분리 |

### Dual Ingress Controller 이해

본 플랫폼은 **두 개의 nginx-ingress**가 운영됩니다:

| 구분 | IngressClassName | NLB | 대상 |
|:---|:---|:---|:---|
| **Public** | `nginx` | Internet-facing | 고객 대상 웹서비스 |
| **Internal** | `nginx-internal` | Internal | 관리 UI (Teleport 경유) |

### 외부 서비스 Ingress

```yaml
spec:
  ingressClassName: nginx               # ← Public NLB 경유
  tls:
    - hosts: [myapp.unifiedmeta.net]
      secretName: myapp-tls
```

### 내부 서비스 Ingress

```yaml
spec:
  ingressClassName: nginx-internal       # ← Internal NLB 경유
  tls:
    - hosts: [admin.unifiedmeta.net]
      secretName: admin-tls
```

### TLS 인증서 자동 발급

```yaml
annotations:
  cert-manager.io/cluster-issuer: letsencrypt-dns01    # ← 반드시 DNS-01 사용
```

> [!WARNING]
> **HTTP-01 challenge를 사용하면 안 됩니다.**
> Pod 내부에서 자신의 Ingress로 HTTP 요청을 보내는 hairpin routing 문제가 발생합니다.
> 반드시 `letsencrypt-dns01` (DNS-01 challenge)을 사용하세요.
> 상세: [cert-manager-http01-hairpin-issue.md](../troubleshooting/cert-manager-http01-hairpin-issue.md)

### 💡 팁

- 하나의 서비스가 **Public + Internal 양쪽**이 필요하면, Ingress를 **2개** 만들되 각각 다른 `ingressClassName`을 사용하세요.
- Keycloak이 좋은 예: Public(OIDC endpoint)과 Internal(Admin Console)을 분리합니다.
- 상세: [05-k8s-traffic-and-tls.md](../architecture/05-k8s-traffic-and-tls.md), [08-nlb-architecture.md](../architecture/08-nlb-architecture.md)

---

## 6. DNS — 자동 등록 이해하기

### 📖 용어 정리

| 용어 | 설명 |
|:---|:---|
| **Route53** | AWS 관리형 DNS 서비스. 도메인의 Hosted Zone을 관리 |
| **Hosted Zone** | Route53에서 하나의 도메인에 대한 DNS 레코드 집합. Public Zone(인터넷)과 Private Zone(VPC 내부) 구분 |
| **ExternalDNS** | K8s Ingress/Service 리소스를 감시하여 DNS 레코드를 자동 생성/삭제하는 컨트롤러 |
| **A 레코드 (Alias)** | 도메인을 IP 또는 AWS 리소스(NLB 등)에 매핑하는 DNS 레코드 |
| **TXT 레코드 (Registry)** | ExternalDNS가 DNS 레코드의 소유권을 주장하기 위해 생성하는 메타데이터 레코드 |
| **CNAME** | 도메인을 다른 도메인에 매핑하는 DNS 레코드. 예: `harbor.unifiedmeta.net` → ALB DNS |

### Hybrid DNS 구조

| 관리 주체 | 대상 | Zone |
|:---|:---|:---|
| **Terraform** | 영구 인프라 레코드 (Harbor, VPC 등) | Public/Private |
| **ExternalDNS** (bootstrap) | Public Ingress 기반 레코드 | Public Zone |
| **ExternalDNS-Private** (bootstrap) | Internal Ingress 기반 레코드 | Private Zone |

### 💡 팁

- Ingress를 올바른 `ingressClassName`으로 만들면, **DNS는 자동으로 등록됩니다**.
- Route53에서 수동으로 DNS를 수정하지 마세요 — **ExternalDNS가 덮어씁니다**.
- Internal 서비스에는 Ingress annotation이 필요할 수 있습니다:
  ```yaml
  annotations:
    external-dns.alpha.kubernetes.io/target: <INTERNAL_NLB_DNS>
  ```
- ExternalDNS가 생성한 TXT 레코드(소유권 마킹)를 절대 삭제하지 마세요.
- 상세: [04-dns-strategy.md](../architecture/04-dns-strategy.md)

---

## 7. Keycloak SSO — 인증을 직접 만들지 마세요

### 📖 용어 정리

| 용어 | 설명 |
|:---|:---|
| **Keycloak** | 오픈소스 IAM(Identity & Access Management) 솔루션. SSO, OIDC, SAML, 멀티테넌트 지원 |
| **SSO (Single Sign-On)** | 한 번 로그인하면 연동된 모든 서비스에 자동 인증되는 방식 |
| **OIDC (OpenID Connect)** | OAuth 2.0 위에 구축된 인증 프로토콜. ID Token으로 사용자 정보를 전달 |
| **Realm** | Keycloak의 테넌트 단위. 사용자, 클라이언트, 롤을 격리하는 논리적 공간 |
| **Client** | Keycloak에 등록된 애플리케이션. 각 서비스(Grafana, ArgoCD 등)는 별도 Client로 등록 |
| **Client Secret** | Client 인증에 사용되는 비밀 키. Confidential Client에서만 사용 |
| **Issuer URL** | OIDC Provider의 기준 URL. 토큰 검증, Discovery 엔드포인트의 시작점 |
| **OIDC Discovery** | `/.well-known/openid-configuration` 경로로 OIDC Provider의 모든 엔드포인트를 자동 검색 |
| **Role Mapping** | Keycloak 그룹/롤을 서비스 내부 권한(Admin, Editor 등)에 매핑하는 설정 |
| **IdP (Identity Provider)** | 사용자 인증을 담당하는 중앙 서비스. 본 플랫폼에서는 Keycloak |

### 핵심 원칙

> **로그인 페이지를 직접 만드는 것은 안티패턴입니다.**
> Keycloak OIDC를 연동하면 SSO가 자동으로 적용됩니다.

### OIDC 연동 체크리스트

1. **Keycloak Admin**에서 `platform` Realm에 Client 등록
2. Client ID, Secret 발급
3. 서비스에서 OIDC 연동 설정

### 연동 정보

| 항목 | 값 |
|:---|:---|
| Issuer URL | `https://keycloak.dev.unifiedmeta.net/realms/platform` |
| Auth URL | `{issuer}/protocol/openid-connect/auth` |
| Token URL | `{issuer}/protocol/openid-connect/token` |
| UserInfo URL | `{issuer}/protocol/openid-connect/userinfo` |
| OIDC Discovery | `{issuer}/.well-known/openid-configuration` |

### Grafana 연동 예시 (참고용)

```yaml
grafana.ini:
  auth.generic_oauth:
    enabled: true
    name: "Keycloak"
    client_id: "grafana"
    client_secret: "<SECRET>"
    scopes: "openid email profile roles"
    auth_url: "https://keycloak.dev.unifiedmeta.net/realms/platform/protocol/openid-connect/auth"
    token_url: "https://keycloak.dev.unifiedmeta.net/realms/platform/protocol/openid-connect/token"
    api_url: "https://keycloak.dev.unifiedmeta.net/realms/platform/protocol/openid-connect/userinfo"
    role_attribute_path: "contains(groups[*], 'admin') && 'Admin' || 'Viewer'"
```

### 💡 팁

- **Role Mapping**: Keycloak 그룹(`admin`, `editor`, `viewer`)을 서비스 Role로 매핑하면 중앙 권한 관리가 가능합니다.
- `client_secret`은 **K8s Secret**이나 **Vault**에 보관하세요. Git에 평문으로 넣지 마세요.
- 새 환경 배포 시 `keycloak.dev.`를 `keycloak.{env}.`로 변경 — `infra-context`를 활용하면 자동화됩니다.
- 상세: [11-keycloak-idp-strategy.md](../architecture/11-keycloak-idp-strategy.md)

---

## 8. Vault — 시크릿을 하드코딩하지 마세요

### 📖 용어 정리

| 용어 | 설명 |
|:---|:---|
| **Vault** | HashiCorp의 시크릿 관리 도구. 암호화, 동적 시크릿 생성, 접근 감사를 중앙에서 관리 |
| **Dynamic Secrets** | 요청 시 생성되고 TTL 후 자동 폐기되는 일회용 자격증명. 예: DB 비밀번호 자동 생성/회전 |
| **KV (Key-Value) Engine** | Vault의 정적 시크릿 저장소. v2는 버전 관리 지원 |
| **Kubernetes Auth** | K8s ServiceAccount 토큰으로 Vault에 인증하는 방식. Pod → Vault 자동 인증 |
| **Vault Agent Sidecar** | Pod 옆에서 실행되며, Vault에서 시크릿을 가져와 파일로 마운트해주는 자동 주입 컨테이너 |
| **Auto-Unseal** | AWS KMS를 사용하여 Vault 재시작 시 자동 잠금 해제. 수동 unseal key 입력 불필요 |
| **Recovery Key** | Auto-Unseal 환경에서 비상 복구에 사용되는 키. 최초 init 시 1회만 출력됨 |
| **PKI Engine** | Vault의 내부 인증서 발급 엔진. self-signed CA 역할 수행 |

### 시크릿 관리 우선순위

```
1순위: Vault Dynamic Secrets (DB 비밀번호 자동 생성/회전)
2순위: Vault KV (정적 시크릿 중앙 관리)
3순위: K8s Secret (Vault 미연동 시 임시 사용)
❌ 절대 금지: Git에 평문 시크릿 커밋
```

### Pod에서 Vault 사용하기 (Kubernetes Auth)

```yaml
# ServiceAccount에 Vault 인증 annotation 추가
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-service
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "my-service"
    vault.hashicorp.com/agent-inject-secret-db: "secret/data/platform/database"
```

### 💡 팁

- DB 비밀번호를 환경변수로 직접 넣지 말고, **Vault Agent Sidecar**가 파일로 마운트하게 하세요.
- Vault의 **Kubernetes Auth**는 이미 활성화되어 있으므로, Role/Policy만 추가하면 됩니다.
- 비밀번호를 Git 히스토리에 남기지 않도록 주의 — 이미 커밋한 경우 `BFG Repo-Cleaner`로 정리하세요.
- 상세: [vault-kms-auto-unseal.md](../vault/vault-kms-auto-unseal.md)

---

## 9. Access Gateway — 자동 서비스 등록

### 📖 용어 정리

| 용어 | 설명 |
|:---|:---|
| **Access Gateway** | 내부 서비스에 대한 통합 접근 제어 계층. 현재 Teleport, 향후 Boundary/Guacamole 교체 가능 |
| **Teleport** | SSH, K8s, DB, Web App 접근을 통합 관리하는 Zero Trust 접근 프록시. 세션 녹화, 감사 로그 지원 |
| **App Access** | Teleport가 웹 애플리케이션에 대한 인증된 프록시를 제공하는 기능 |
| **service_endpoint** | 본 플랫폼의 표준 인터페이스 패턴. Terraform output으로 서비스 접속 정보를 노출하면 Access Gateway가 자동 수집 |
| **Solution-Agnostic** | 특정 솔루션에 의존하지 않는 설계. 서비스 코드 변경 없이 접근 제어 솔루션 교체 가능 |
| **Remote State** | Terraform이 다른 스택의 output을 참조하는 방식. `80-access-gateway`가 각 서비스 스택의 endpoint를 수집하는 방법 |
| **try() 함수** | Terraform에서 에러 발생 시 기본값을 반환하는 함수. 미배포 스택 참조 시 안전하게 null 처리 |

### service_endpoint 패턴

내부 서비스에 Teleport App Access를 걸려면, 서비스 스택에 `service_endpoint` output만 추가하세요.

```hcl
# 서비스 스택의 outputs.tf
output "service_endpoint" {
  value = {
    name     = "my-service"
    uri      = "https://my-service.unifiedmeta.net"
    type     = "web"      # web | api | db
    internal = true
  }
}
```

이렇게 하면 `80-access-gateway` 스택이 자동으로 수집하여 Teleport에 등록합니다.

### 💡 팁

- **느슨한 결합**: 서비스는 Teleport의 존재를 알 필요가 없습니다. `output`만 정의하면 됩니다.
- 솔루션 교체(Teleport → Boundary 등) 시에도 **서비스 코드 변경이 없습니다**.
- `try()` 함수로 안전하게 수집하므로, 미배포 스택은 null 반환되어 무시됩니다.
- 상세: [13-access-gateway-architecture.md](../architecture/13-access-gateway-architecture.md)

---

## 10. Observability — 모니터링/로그/트레이스 연동

### 📖 용어 정리

| 용어 | 설명 |
|:---|:---|
| **Observability (관측성)** | 시스템의 내부 상태를 메트릭/로그/트레이스 3가지 신호로 외부에서 파악하는 능력 |
| **Prometheus** | Pull 기반 메트릭 수집 시스템. `/metrics` 엔드포인트를 주기적으로 스크래핑 |
| **ServiceMonitor** | Prometheus Operator의 CRD. 어떤 Service에서 메트릭을 수집할지 선언적으로 정의 |
| **Loki** | Grafana Labs의 로그 집계 시스템. 인덱스 최소화로 비용 효율적. 라벨 기반 쿼리(LogQL) |
| **Promtail** | Loki용 로그 수집 에이전트. DaemonSet으로 모든 Node의 Pod 로그를 자동 수집 |
| **Tempo** | Grafana Labs의 분산 트레이싱 백엔드. OpenTelemetry 호환. 요청의 서비스 간 흐름 추적 |
| **OpenTelemetry (OTel)** | CNCF의 관측성 표준. 메트릭/로그/트레이스를 수집하는 통합 SDK/Collector |
| **traceID** | 하나의 요청이 여러 서비스를 거치는 전체 경로를 추적하는 고유 ID |
| **Grafana** | 메트릭/로그/트레이스를 통합 시각화하는 대시보드 도구. SSO 연동(Keycloak) 지원 |
| **Scraping** | Prometheus가 타겟의 `/metrics` 엔드포인트를 주기적으로 호출하여 메트릭을 수집하는 동작 |

### 이미 구축된 관측성 스택

| 도구 | 역할 | 위치 |
|:---|:---|:---|
| **Prometheus** | 메트릭 수집 | `monitoring` NS |
| **Loki** | 로그 집계 | `monitoring` NS |
| **Tempo** | 분산 트레이스 | `monitoring` NS |
| **Grafana** | 통합 시각화 | `monitoring` NS |
| **Promtail** | 로그 수집 에이전트 | 모든 Node |

### 메트릭 자동 수집 (ServiceMonitor)

Prometheus가 자동으로 메트릭을 수집하게 하려면:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-service
  namespace: my-service
  labels:
    release: monitoring     # ← 이 레이블이 있어야 Prometheus가 감지
spec:
  selector:
    matchLabels:
      app: my-service
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics
```

### 로그 수집

**별도 설정 불필요** — Promtail DaemonSet이 모든 Pod의 stdout/stderr를 자동 수집합니다.

단, 구조화된 로그를 위해:

```json
// ✅ 권장: JSON 형식 로그
{"level":"info","msg":"request handled","traceID":"abc123","duration_ms":42}

// ❌ 비권장: 비구조화 로그
2026-02-09 INFO request handled
```

### 분산 트레이스 (Tempo)

서비스에서 OpenTelemetry SDK를 사용하면 Tempo로 자동 전송됩니다:

```yaml
# 환경변수 설정
OTEL_EXPORTER_OTLP_ENDPOINT: "http://tempo.monitoring.svc.cluster.local:4317"
OTEL_SERVICE_NAME: "my-service"
```

### 💡 팁

- 로그에 **traceID**를 포함하면, Grafana에서 **로그 → 트레이스** 간 자동 연결이 됩니다 (이미 설정됨).
- 서비스 메트릭 포트를 `/metrics` 경로로 노출하면 **자동 수집** — ServiceMonitor만 추가하세요.
- Grafana 대시보드 ID `13770`(Pod Monitoring)을 import하면 서비스 기본 모니터링이 즉시 가능합니다.

---

## 11. Cilium NetworkPolicy — L7 수준 접근 제어

### 📖 용어 정리

| 용어 | 설명 |
|:---|:---|
| **Cilium** | eBPF 기반 CNI(Container Network Interface) 플러그인. 네트워킹, 보안, 관측성을 커널 레벨에서 처리 |
| **eBPF** | Linux 커널에서 실행되는 샌드박스 프로그램. 커널 수정 없이 네트워크 패킷 처리, 보안 정책 적용 가능 |
| **ENI Mode** | Cilium이 AWS ENI(Elastic Network Interface)를 직접 관리하여 Pod에 VPC IP를 할당하는 모드 |
| **VPC-native Pod IP** | Pod IP가 VPC 서브넷 IP와 동일. overlay 없이 VPC 내 어디서든 직접 라우팅 가능 |
| **L3/L4 NetworkPolicy** | IP 주소(L3)와 포트(L4) 기반의 기본 K8s 네트워크 정책 |
| **L7 NetworkPolicy** | HTTP method, path, header 수준까지 제어 가능한 Cilium 전용 확장 정책 |
| **CiliumNetworkPolicy** | Cilium의 CRD. K8s 기본 NetworkPolicy보다 세밀한 L7 규칙 지원 |
| **Hubble** | Cilium의 실시간 네트워크 관측성 도구. Pod 간 트래픽 흐름을 시각화 |
| **endpointSelector** | CiliumNetworkPolicy에서 정책 대상 Pod을 라벨로 선택하는 필드 |

### 기존 NetworkPolicy 대비 장점

Cilium은 **L7 수준**(HTTP path, header)까지 제어할 수 있습니다.

### 예시: Public Ingress에서 Admin 경로 차단

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: my-service-l7-policy
  namespace: my-service
spec:
  endpointSelector:
    matchLabels:
      app: my-service
  ingress:
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: ingress-nginx       # Public ingress
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
          rules:
            http:
              - method: GET
                path: "/api/.*"          # ✅ API 경로만 허용
              - method: GET
                path: "/health"          # ✅ 헬스체크 허용
                                         # /admin/* 는 암묵적 차단
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: ingress-nginx-internal  # Internal ingress
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
          # Internal은 모든 경로 허용 (Admin 포함)
```

### 💡 팁

- **Keycloak 패턴을 참고하세요**: Public에서는 OIDC 엔드포인트만 노출, Admin은 Internal에서만 접근 가능.
- `hubble observe --namespace my-service` 명령으로 실시간 트래픽 흐름을 관찰할 수 있습니다.
- Pod IP가 VPC-native(Cilium ENI)이므로, **Security Group 연동도 가능**합니다.
- 상세: [17-cilium-cni-architecture.md](../architecture/17-cilium-cni-architecture.md)

---

## 12. 스토리지 — Longhorn 활용 팁

### 📖 용어 정리

| 용어 | 설명 |
|:---|:---|
| **Longhorn** | Rancher에서 만든 K8s 네이티브 분산 블록 스토리지. 자동 복제, 스냅샷, S3 백업 지원 |
| **PVC (PersistentVolumeClaim)** | Pod이 스토리지를 요청하는 K8s 리소스. StorageClass에 따라 자동 프로비저닝 |
| **PV (PersistentVolume)** | 실제 스토리지를 나타내는 K8s 리소스. PVC와 바인딩되어 Pod에 마운트 |
| **StorageClass** | 스토리지 프로비저닝 방식을 정의. 본 플랫폼은 `longhorn` StorageClass 사용 |
| **Replica** | Longhorn이 볼륨 데이터를 복제하는 수. 기본 3으로 설정되어 1 Node 장애에도 안전 |
| **ReadWriteOnce (RWO)** | 하나의 Node에서만 읽기/쓰기 가능한 접근 모드. 대부분의 스테이트풀 서비스에 적합 |

### PVC 사용

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-service-data
  namespace: my-service
spec:
  storageClassName: longhorn          # ← Longhorn StorageClass 사용
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 10Gi
```

### 💡 팁

- StorageClass는 **`longhorn`**을 사용하세요. 기본 설정되어 있습니다.
- Longhorn은 S3 자동 백업이 설정되어 있습니다 (`dev-meta-longhorn-backup` 버킷).
- Replica 수는 기본 3으로 설정되어 있어 Worker Node 1대 장애 시에도 데이터가 안전합니다.
- 대량 데이터 저장 시에는 EC2 기반 독립 DB(60-postgres 패턴) 사용을 고려하세요.

---

## 13. Harbor — 이미지/차트 레지스트리 활용

### 📖 용어 정리

| 용어 | 설명 |
|:---|:---|
| **Harbor** | VMware가 만든 오픈소스 컨테이너 레지스트리. 이미지 저장, 취약점 스캔, 프록시 캐시, RBAC 지원 |
| **OCI (Open Container Initiative)** | 컨테이너 이미지 및 런타임의 개방형 표준. Helm Chart도 OCI 형식으로 저장 가능 |
| **Container Image** | 애플리케이션과 실행 환경이 패키징된 불변 이미지. `docker build`로 생성 |
| **프록시 캐시 (Proxy Cache)** | Harbor가 Docker Hub 등 공용 레지스트리의 이미지를 캐싱. Rate Limit 회피 + 폐쇄망 지원 |
| **Garbage Collection** | 미사용(untagged/unreferenced) 이미지를 자동 정리하여 스토리지를 확보하는 기능 |
| **chartrepo** | Harbor에서 Helm Chart를 저장하는 엔드포인트. `https://harbor.unifiedmeta.net/chartrepo/library` |

### 이미지 Push/Pull

```bash
# 로그인
docker login harbor.unifiedmeta.net

# 이미지 태깅 및 푸시
docker tag my-app:latest harbor.unifiedmeta.net/platform/my-app:1.0.0
docker push harbor.unifiedmeta.net/platform/my-app:1.0.0
```

### Helm Chart 저장

```bash
# Chart 패키징 및 업로드
helm package ./my-chart
helm push my-chart-1.0.0.tgz oci://harbor.unifiedmeta.net/platform
```

### 💡 팁

- 프로젝트 이름은 팀/서비스에 맞게 Harbor에서 생성하세요 (예: `platform`, `apps`).
- Harbor의 **프록시 캐시**를 활용하면 Docker Hub Rate Limit에 걸리지 않습니다.
- ArgoCD App의 `repoURL`을 Harbor로 설정하면 **폐쇄망 환경에서도 동일하게 동작**합니다.

---

## 14. 안티패턴 — 반드시 피해야 할 것들

| # | ❌ 안티패턴 | ✅ 올바른 방법 |
|:---:|:---|:---|
| 1 | 인증 로직 직접 구현 | **Keycloak OIDC** 연동 |
| 2 | 시크릿을 Git에 커밋 | **Vault** 또는 K8s Secret (외부 주입) |
| 3 | 도메인/ARN 하드코딩 | **infra-context** Secret 참조 |
| 4 | HTTP-01 TLS challenge 사용 | **DNS-01 challenge** 사용 |
| 5 | Route53 DNS 수동 수정 | **ExternalDNS**에 위임 (Ingress 생성만) |
| 6 | `bootstrap/`에 앱 배치 | **`apps/`** 디렉토리 사용 |
| 7 | Terraform으로 K8s 앱 관리 | **ArgoCD**가 앱 전담 관리 |
| 8 | Overlay 네트워크 전제 코드 | Pod IP는 **VPC-native** (Cilium ENI) |
| 9 | kube-proxy iptable 의존 | Cilium **eBPF** 기반 서비스 라우팅 |
| 10 | 로그를 비구조화 텍스트로 출력 | **JSON 형식** 구조화 로그 |

---

## 15. 신규 서비스 체크리스트

### 배포 전 확인

- [ ] 네이밍 컨벤션 준수 (`{env}-{project}-{workload}-{resource}`)
- [ ] ArgoCD App을 `gitops-apps/apps/`에 생성
- [ ] Sync Wave 50+ 설정
- [ ] Helm Chart를 Harbor에 Push

### 네트워크/접근

- [ ] Ingress 유형 결정 (Public: `nginx` / Internal: `nginx-internal`)
- [ ] TLS: `letsencrypt-dns01` ClusterIssuer 사용
- [ ] 내부 서비스면 `service_endpoint` output 추가 (Access Gateway 자동 등록)
- [ ] CiliumNetworkPolicy 작성 (L7 경로 기반 접근 제어)

### 인증/보안

- [ ] Keycloak OIDC Client 등록 (직접 인증 구현 ❌)
- [ ] 시크릿은 Vault 또는 K8s Secret으로 외부 주입
- [ ] Git 히스토리에 평문 시크릿 없는지 확인

### 관측성

- [ ] ServiceMonitor 추가 (Prometheus 메트릭 자동 수집)
- [ ] 로그 JSON 형식 출력 (Loki 자동 수집)
- [ ] OpenTelemetry 트레이스 설정 (Tempo 연동)
- [ ] traceID를 로그에 포함 (로그↔트레이스 연결)

### 스토리지/데이터

- [ ] PVC 사용 시 StorageClass `longhorn` 지정
- [ ] DB 필요 시 기존 인프라 활용 검토 (PostgreSQL, Neo4j, OpenSearch)

---

## 📎 관련 문서

| 문서 | 설명 |
|:---|:---|
| [웹서비스 온보딩 가이드](web-service-onboarding.md) | 구체적 배포 절차 (Step-by-step) |
| [Post-Deployment 운영 가이드](post-deployment-operations-guide.md) | 배포 후 초기 설정 |
| [Architecture README](../architecture/README.md) | 아키텍처 문서 전체 인덱스 |
| [GitOps 역할 분담](../architecture/10-gitops-role-division.md) | Terraform vs ArgoCD 경계 |
| [Bootstrap 전략](../architecture/09-bootstrap-strategy.md) | infra-context 패턴 상세 |
| [Access Gateway](../architecture/13-access-gateway-architecture.md) | service_endpoint 패턴 상세 |
| [Keycloak IdP](../architecture/11-keycloak-idp-strategy.md) | SSO 연동 전략 |
| [Cilium CNI](../architecture/17-cilium-cni-architecture.md) | eBPF 네트워킹 |

---

## 변경 이력

| 버전 | 날짜 | 변경 내용 |
|:---|:---|:---|
| 1.0 | 2026-02-09 | 초안 작성 — 15개 영역 아키텍처 활용 팁 |
| 1.1 | 2026-02-09 | 각 섹션별 📖 용어 정리(Glossary) 추가 |
