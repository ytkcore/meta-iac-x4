# UnifiedMeta v0.6 — 고도화 전략

> **문서 상태**: Draft  
> **기준 버전**: v0.5 (2026-02-12 기준 소스 코드 전수 분석)  
> **작성일**: 2026-02-12  
> **목표**: CSP 독립성 확보 · 솔루션 패키징 레이어 체계화 · 운영 최적화

---

## 1. 현재 형상 진단

### 1.1 CSP 의존성 정밀 분류

각 컴포넌트를 아래 **세 가지 분류** 기준으로 구분합니다.

| 분류 | 의미 | v0.6 대응 |
|:---:|------|----------|
| 🔴 | **솔루션 자체가 CSP 종속** — 해당 CSP 고유 서비스, 등가 대체재로 교체 필수 | Terraform 재작성 (v0.7~v0.8) |
| 🟡 | **솔루션은 CSP 독립, 코드가 AWS 고정** — 설정/값만 변경하면 이식 가능 | **v0.6 values 분리로 해결** |
| 🟢 | **완전 CSP 독립** — 현재 코드 그대로 어떤 K8s에서든 동작 | 변경 불필요 |

---

### 1.2 🔴 솔루션 자체가 CSP 종속 — 등가 구현 필요

> AWS 고유 서비스로, 다른 CSP에서는 동등 서비스로 **재작성** 필요.  
> 단, **아키텍처 패턴** (서브넷 티어링, SG 규칙 설계 등)은 CSP 간 재활용 가능.

| 컴포넌트 | AWS (현재) | Azure | GCP | On-Prem |
|---------|-----------|-------|-----|--------|
| VPC / Subnet / NAT | AWS VPC | Azure VNet | GCP VPC | VLAN / OVS |
| IAM Roles & Policies | AWS IAM | Azure AD (Entra ID) | GCP IAM | Keycloak RBAC |
| Security Groups | AWS SG | Azure NSG | GCP Firewall Rules | iptables / nftables |
| WAF | AWS WAF v2 | Azure WAF | Cloud Armor | ModSecurity |
| Compute Instances | AWS EC2 | Azure VM | GCE | Bare-metal / VMware |
| Golden Image | AWS AMI + Packer | Azure Image + Packer | GCE Image + Packer | Packer + QCOW2 |
| Load Balancer (L7) | AWS ALB | Azure App GW | GCP HTTP(S) LB | HAProxy / Nginx |
| DNS Zone | AWS Route53 | Azure DNS | Cloud DNS | CoreDNS / BIND |
| Private Endpoint | AWS PrivateLink | Azure Private Link | Private Service Connect | 내부 라우팅 |
| 원격 관리 | AWS SSM | Azure Bastion | GCP OS Login | Teleport / SSH 직접 |

📂 관련 코드: `modules/vpc`, `modules/security-groups`, `modules/ec2-instance`, `stacks/dev/00~20`

---

### 1.3 🟡 솔루션은 CSP 독립, 현재 코드만 AWS 고정

> **오픈소스/CNCF** 프로젝트로 어떤 CSP에서든 동작하지만,  
> Helm values 또는 K8s 매니페스트에 AWS 전용 설정이 **하드코딩**되어 있습니다.

| 솔루션 | AWS 고정 설정 | 이식 방안 |
|--------|-------------|----------|
| Nginx Ingress Controller | • `aws-load-balancer-type: external`<br>• `aws-load-balancer-scheme: internet-facing`<br>• `aws-load-balancer-nlb-target-type: ip`<br>• `aws-load-balancer-internal: true`<br>• `aws-load-balancer-scheme: internal`<br>• `aws-load-balancer-cross-zone-load-balancing-enabled: true` | • Azure: `azure-load-balancer-*` annotations<br>• GCP: GKE BackendConfig / NEG annotations<br>• On-Prem: MetalLB (L2/BGP) |
| HashiCorp Vault (OSS) | • `seal "awskms"`<br>• `region: ap-northeast-2`<br>• `kms_key_id: fcaa...` | • Azure: `seal "azurekeyvault"`<br>• GCP: `seal "gcpckms"`<br>• On-Prem: Shamir 또는 Transit auto-unseal |
| Longhorn (CNCF) | • `backupTarget: s3://...`<br>• `backupTargetCredentialSecret` | • Azure: Azure Blob (S3 gateway)<br>• GCP: GCS (S3 interop mode)<br>• On-Prem: MinIO 또는 NFS |
| cert-manager (CNCF) | • `dns01.route53 { hostedZoneID }`<br>• `nameservers: 10.0.0.2` | • Azure: `dns01.azureDNS`<br>• GCP: `dns01.cloudDNS`<br>• On-Prem: `dns01.cloudflare` 또는 HTTP-01 |
| ExternalDNS (CNCF) | • `provider: aws`<br>• `region: ap-northeast-2`<br>• `image: public.ecr.aws` | • Azure: `provider: azure`<br>• GCP: `provider: google`<br>• On-Prem: `provider: cloudflare` 또는 CoreDNS |
| RKE2 (Rancher) | • EC2 userdata<br>• AWS nodegroup 설정 | • Azure: VM custom data<br>• GCP: VM metadata startup-script<br>• On-Prem: Bare-metal / PXE boot |
| Teleport v18 (OSS) | • ALB Target Group<br>• SSM RunCommand 연동 | • Azure: Azure LB 연동<br>• GCP: GCP LB 연동<br>• On-Prem: Nginx reverse proxy |

> **이 7개 솔루션 (10개 설정 포인트)이 v0.6 핵심 타깃.**  
> `values/` 프로파일로 분리하면 코드 변경 없이 CSP 전환 달성.

---

### 1.4 🟢 완전 CSP 독립 — 현재 코드 그대로 이식 가능

> CSP 종속 설정 없음. K8s API만 있으면 어디서든 동작합니다.

| 컴포넌트 | 솔루션 | 검증 근거 |
|---------|------|----------|
| ArgoCD | ArgoCD (CNCF) | Git repo URL만 참조 |
| Prometheus | kube-prometheus-stack | Longhorn PVC 사용, CSP API 없음 |
| Grafana | Grafana OSS | Keycloak OIDC (자체 서비스 간 통신) |
| Loki | Grafana Loki | filesystem 스토리지 + Longhorn PVC |
| Tempo | Grafana Tempo | OTLP receiver, 로컬 스토리지 |
| Promtail | Grafana Promtail | DaemonSet 로그 수집 → Loki |
| Keycloak | Keycloak v25 | 자체 PostgreSQL, K8s Ingress만 사용 |
| Rancher | Rancher (SUSE) | K8s 관리 UI, CSP API 없음 |
| AIPP 앱 | 자체 솔루션 | 순수 K8s 워크로드 |
| Landing Page | Static HTML + Nginx | ConfigMap 마운트 |
| Opstart | Flask Dashboard | K8s API만 사용 |

---

### 1.5 요약

| 분류 | 수량 | 포함 컴포넌트 | 대응 레이어 | v0.6 대응 |
|:---:|:---:|-------------|-----------|:---------:|
| 🔴 | 10개 | VPC, IAM, SG, WAF, EC2, AMI, ALB, Route53, VPC Endpoints, SSM | Terraform | v0.7~v0.8 |
| 🟡 | 10개 | Nginx Ingress ×2, Vault, Longhorn, cert-manager ×2, external-dns ×2, RKE2, Teleport | GitOps (values) | **v0.6 대응** ✅ |
| 🟢 | 11개 | ArgoCD, Prometheus, Grafana, Loki, Tempo, Promtail, Keycloak, Rancher, AIPP, LP, Opstart | GitOps (공통) | 변경 불필요 ✅ |

> **전체 31개 컴포넌트 중 21개 (68%)가 CSP 독립 가능 또는 이미 독립.**  
> 🟡 영역 10개의 values 분리만으로 **GitOps 레이어 100% CSP 독립** 달성 가능.

---

### 1.6 v0.6 CSP 소스코드 최적화 범위 결정

> **v0.6에서는 🟡 (Values 분리)만 실행하고, 🔴 (Terraform 재작성)는 v0.7 이후로 유보합니다.**

이 결정의 근거:

| # | 근거 | 설명 |
|:-:|------|------|
| 1 | **타깃 CSP 미확정** | 🔴 Terraform 재작성은 실제 배포할 CSP가 확정되어야 의미가 있음. Azure/GCP용 모듈을 작성해도 실 환경 검증 없이는 품질 보증 불가 |
| 2 | **즉시 효과 vs 장기 투자** | 🟡 Values 분리 (1~2주)만으로 GitOps 레이어 100% CSP 독립 달성. 투입 대비 효과가 압도적 |
| 3 | **고객 납품 우선** | Helm Chart(Tier 3)와 운영 자동화가 매출에 직결. CSP 추상화는 내부 아키텍처 품질이지만 Helm Chart는 고객 가치 |
| 4 | **운영 안정성 보전** | 16개 Terraform 모듈 동시 리팩토링은 v0.5 운영 환경에 파괴 리스크. 점진적 전환 원칙에 부합 |

```
v0.6 범위                          v0.7~v0.8 범위
━━━━━━━━━━━━━━━━━━━               ━━━━━━━━━━━━━━━━━━━
🟡 GitOps values 분리 (10개)        🔴 Terraform Provider 분리 (16개)
   → 1~2주, 리스크 낮음                → 수개월, 타깃 CSP 확정 후
   → 검증 가능 (기존 환경 유지)         → 실 CSP 환경 필요
```

> [!IMPORTANT]
> **🔴 영역은 "하지 않는 것"이 아니라 "타이밍을 맞추는 것"입니다.**
> 타깃 CSP 계약이 확정되면 1.2 매트릭스를 기반으로 즉시 착수할 수 있도록 설계 경계를 v0.6에서 확정합니다.

---

## 2. v0.6 고도화 전략 (5대 핵심)

### 2.1 GitOps CSP 추상화 — Values 프로파일 도입

**현재 문제**

```yaml
# nginx-ingress.yaml — AWS에 하드코딩
service.beta.kubernetes.io/aws-load-balancer-type: "external"
service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
```

**해결 방향**: CSP별 Values 프로파일 분리

```
gitops-apps/
└── bootstrap/
    ├── nginx-ingress.yaml              ← ArgoCD App (valueFiles 참조)
    └── values/
        ├── nginx-ingress-aws.yaml      ← AWS LB annotations
        ├── nginx-ingress-azure.yaml    ← Azure LB annotations
        └── nginx-ingress-bare.yaml     ← MetalLB / On-Prem
```

**분리 대상** (총 4개):

| 컴포넌트 | 현재 AWS 종속 설정 | 분리할 항목 |
|---------|:-----------------|-----------|
| Nginx Ingress (Public) | LB type, scheme, target-type | Service annotations |
| Nginx Ingress (Internal) | LB internal, scheme | Service annotations |
| Vault | `seal "awskms"` + region + kms_key_id | Seal stanza 전체 |
| Longhorn | `backupTarget: s3://` | Backup target URL |

> ArgoCD Application에서 `valueFiles: [values/nginx-ingress-{{CSP}}.yaml]` 형태로 환경 전환

---

### 2.2 Terraform Provider 추상화 — CSP 어댑터 패턴

**현재**: 모든 16개 모듈이 `provider "aws"` 직접 사용

**v0.6 방향**: 구조 설계만, 실행은 v0.7~v0.8

```
stacks/
├── aws/                ← AWS 구현체 (L1~L2)
│   ├── 00-network/
│   ├── 05-security/
│   ├── 10-golden-image/
│   ├── 15-access-control/
│   └── 20-waf/
├── azure/              ← Azure 구현체 (향후)
│   └── 00-network/
├── common/             ← CSP 공통 (L3)
│   ├── 50-rke2/
│   ├── 55-bootstrap/
│   └── 80-access-gateway/
└── dev/                ← 현재 → aws/dev 로 이동 예정
```

> **v0.6 산출물**: CSP-specific vs Portable 경계 확정 문서. 코드 이동은 하지 않음.

---

### 2.3 솔루션 패키징 — 3-Tier 전략

고객 납품 시나리오에 맞는 패키징 레이어:

```
  ╔═══════════════════════════════════════════════════════╗
  ║  Tier 1: Full Stack                                   ║
  ║  IaC Foundation + Platform + AIPP Solution             ║
  ║  → 자체 CSP 계정을 보유한 대기업/공공                    ║
  ╠═══════════════════════════════════════════════════════╣
  ║  Tier 2: Platform + App                                ║
  ║  K8s Cluster 위에 Platform Services + AIPP             ║
  ║  → K8s 인프라는 보유, 플랫폼 서비스 부재                 ║
  ╠═══════════════════════════════════════════════════════╣
  ║  Tier 3: App Only                                      ║
  ║  AIPP K8s Manifests + Helm Chart                       ║
  ║  → 자체 K8s + Observability 보유 기업                   ║
  ╚═══════════════════════════════════════════════════════╝
```

**v0.6 실행 항목**:

| 산출물 | 설명 | 상태 |
|--------|------|:----:|
| AIPP Helm Chart | `charts/aipp/` — Tier 3 독립 배포용 | 🆕 |
| Platform Bootstrap | Tier 2용 원클릭 플랫폼 구성 | 🆕 |
| IaC Quickstart | `make apply-all-auto` 기반 Tier 1 | ✅ 보강 |
| 패키징 매트릭스 | Tier별 포함/제외 정의서 | 🆕 |

**AIPP Helm Chart 구조** (Tier 3 핵심):

```
charts/aipp/
├── Chart.yaml
├── values.yaml                  ← 최소 구성 (어떤 K8s든 즉시 구동)
├── values-full.yaml             ← Vault + Longhorn + cert-manager 통합
├── templates/
│   ├── namespace.yaml
│   ├── pgvector.yaml            ← StatefulSet
│   ├── redis.yaml
│   ├── rabbitmq.yaml
│   ├── backend.yaml
│   ├── frontend.yaml
│   ├── linker.yaml              ← GPU 조건부 (linker.enabled)
│   ├── ingress.yaml
│   └── _helpers.tpl
└── README.md
```

**설계 원칙**:
- `values.yaml`만으로 외부 의존 없이 즉시 구동
- `values-full.yaml`로 플랫폼 통합 활성화 (Vault sidecar, Longhorn PVC)
- GPU 노드 유무에 따른 조건부 배포 (`linker.enabled: false`)

---

### 2.4 운영 자동화 성숙도 향상

| 영역 | v0.5 (현재) | v0.6 (목표) |
|------|:-----------|:-----------|
| CI/CD | Git push → ArgoCD auto-sync | + Image Tag 자동화 (ArgoCD Image Updater) |
| Secret | Vault 수동 주입 | + Vault Dynamic Secrets (DB creds auto-rotation) |
| Backup | Longhorn S3 백업 (수동) | + Velero 스케줄 백업 (K8s + PV 통합) |
| Alerting | Grafana 기본값 | + 핵심 SLO 기반 Alert Rule 체계화 |
| 문서화 | 가이드 Markdown | + Runbook 자동화 (Alert → Runbook 링크) |

**우선순위 Top 3**:

1. **Velero 스케줄 백업** (높음)
   ```yaml
   schedule:
     daily-backup:
       schedule: "0 2 * * *"    # 매일 02:00 UTC
       template:
         includedNamespaces: [aipp, apps, vault]
         snapshotVolumes: true
   ```

2. **Grafana Alert SLO 체계화** (중간)
   - AIPP 서비스별 핵심 SLO: Pod Restart, 5xx Rate, Latency P99
   - Runbook URL 연결

3. **ArgoCD Image Updater** (낮음)
   - Harbor push 시 K8s 매니페스트 자동 업데이트
   - 선행 조건: Harbor CI 파이프라인 구축

---

### 2.5 개발/검증 환경 효율화

| 영역 | v0.5 | v0.6 |
|------|:-----|:-----|
| 로컬 개발 | `python3 -m http.server` | k3d/kind 기반 로컬 미니 클러스터 |
| E2E 테스트 | 수동 검증 | `make verify` 타겟 (kubectl health check 자동화) |
| 환경 복제 | 불가 | `stacks/staging/` 추가 (dev와 동일 구조, 축소 스펙) |
| 비용 최적화 | 상시 운영 | Karpenter/KEDA 기반 스케일링 (GPU on-demand) |

---

## 3. 로드맵

| Phase | 작업 | 기간 | 선행 조건 | 관련 전략 |
|:-----:|------|:----:|----------|:---------:|
| **1. 설계** | CSP 의존성 경계 문서화 | 3일 | — | 전략 1, 2 |
| | 패키징 매트릭스 정의 | 2일 | 경계 문서화 완료 | 전략 3 |
| | Helm Chart 구조 설계 | 3일 | 경계 문서화 완료 | 전략 3 |
| **2. 구현** | GitOps values 프로파일 분리 | 3일 | Helm 설계 완료 | 전략 1 |
| | AIPP Helm Chart 작성 | 5일 | Helm 설계 완료 | 전략 3 |
| | Velero 스케줄 백업 구성 | 2일 | values 분리 완료 | 전략 4 |
| **3. 검증** | Tier 3 독립 배포 테스트 | 3일 | Helm Chart 완료 | 전략 3 |
| | Alert SLO 체계화 | 3일 | Velero 완료 | 전략 4 |
| | `make verify` 자동화 | 2일 | Tier 3 테스트 완료 | 전략 5 |

---

## 4. 실행 원칙

| 원칙 | 설명 |
|------|------|
| **문서화 우선** | Terraform 리팩토링(전략 2)은 설계만, 코드 이동은 v0.7 |
| **점진적 전환** | v0.5 운영 환경이 깨지지 않는 범위에서만 변경 |
| **Helm Chart 최우선** | 고객 납품에 직결되는 Tier 3 패키징이 최고 ROI |
| **설정 레벨부터** | 코드 구조 변경 전에 values 파일 분리로 효과 확보 |
| **검증 수반** | 모든 고도화 포인트마다 `make verify` 또는 E2E 테스트 |
