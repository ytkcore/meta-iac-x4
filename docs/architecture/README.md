# Architecture Documentation

이 디렉토리는 플랫폼의 아키텍처 설계 문서를 포함합니다.  
문서는 플랫폼 고도화 과정의 논리적 흐름에 따라 **넘버링**되어 있으며, 순서대로 읽으면 전체 아키텍처의 진화를 이해할 수 있습니다.

---

## 문서 구조

### Phase 1: Foundation — 인프라 기반

| # | 문서 | 설명 |
|---|------|------|
| 01 | [naming-convention](01-naming-convention.md) | AWS 리소스 네이밍 컨벤션 표준 (`{env}-{project}-{workload}-{resource}`) |
| 02 | [vpc-endpoint-strategy](02-vpc-endpoint-strategy.md) | VPC PrivateLink 전략 — 폐쇄망 내 SSM/S3 통신 |
| 03 | [golden-image-strategy](03-golden-image-strategy.md) | Packer 기반 불변 AMI 전략 — Docker, SSM Agent 사전 설치 |
| 04 | [dns-strategy](04-dns-strategy.md) | Hybrid DNS — Terraform(Static) + ExternalDNS(Dynamic) 역할 분담 |

### Phase 2: Kubernetes Core — 클러스터 운영

| # | 문서 | 설명 |
|---|------|------|
| 05 | [k8s-traffic-and-tls](05-k8s-traffic-and-tls.md) | North-South / East-West 트래픽 분리, ACM + cert-manager 하이브리드 TLS |
| 06 | [rke2-optimization-guide](06-rke2-optimization-guide.md) | RKE2 Static Manifests 기반 CCM 자동 주입, 부트스트랩 최적화 |
| 07 | [cloud-provider-migration-report](07-cloud-provider-migration-report.md) | In-tree → Out-of-tree CCM 마이그레이션 기술 분석 |
| 08 | [nlb-architecture](08-nlb-architecture.md) | Dual NLB (Public/Internal) + nginx-ingress, Instance vs IP mode 비교 |

### Phase 3: GitOps & Delivery — 배포 체계

| # | 문서 | 설명 |
|---|------|------|
| 09 | [bootstrap-strategy](09-bootstrap-strategy.md) | God Mode → Hybrid → **Pure GitOps** 부트스트랩 진화, Infra Context 패턴 |
| 10 | [gitops-role-division](10-gitops-role-division.md) | Terraform(인프라 레이어) vs ArgoCD(앱 레이어) 역할 분담 기준 |

### Phase 4: Identity & Zero-Trust — 인증/인가 고도화

| # | 문서 | 설명 |
|---|------|------|
| 11 | [keycloak-idp-strategy](11-keycloak-idp-strategy.md) | Keycloak 통합 IdP — SSO, OIDC, IRSA 연동 전략 |
| 12 | [platform-identity-architecture](12-platform-identity-architecture.md) | 4-Layer Identity Stack — Keycloak + SPIRE + Vault + Teleport |
| 13 | [access-gateway-architecture](13-access-gateway-architecture.md) | 솔루션 독립적 접근 제어 — `service_endpoint` 패턴, 80-access-gateway |
| 14 | [future-roadmap](14-future-roadmap.md) | 고도화 로드맵 — ALBC, Keycloak, Vault, SPIRE, Guacamole 도입 계획 |
| 15 | [teleport-replacement-strategy](15-teleport-replacement-strategy.md) | Teleport 교체 전략 — 솔루션 평가 및 마이그레이션 계획 |
| 16 | [architecture-evolution-decision](16-architecture-evolution-decision.md) | 최종 의사결정 — 전체 아키텍처 고도화 결정 흐름 |

### Phase 5: Network Evolution — 네트워크 기반 전환

| # | 문서 | 설명 |
|---|------|------|
| 17 | [cilium-cni-architecture](17-cilium-cni-architecture.md) | Cilium ENI Mode — Canal→Cilium 전환, eBPF 기반 VPC-native Pod 네트워킹 |

---

## 현재 스택 구조

```
00-network       05-security      10-golden-image    15-access-control
20-waf           30-bastion       40-harbor          50-rke2
55-bootstrap     60-postgres      61-neo4j           62-opensearch
70-observability 80-access-gateway
```

## 기타 리소스

| 파일 | 설명 |
|------|------|
| [gitops-architecture.png](gitops-architecture.png) | GitOps 아키텍처 다이어그램 (이미지) |
| [security/](security/) | 보안 관련 하위 문서 |
