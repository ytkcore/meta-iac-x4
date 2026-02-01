# 55-Bootstrap 스택 명세서 (Stack Specification)

## 1. 개요 (Overview)
이 스택은 클러스터 초기 구성 단계의 핵심으로, **ArgoCD를 배포**하고 GitOps 기반의 애플리케이션 라이프사이클 관리를 시작합니다. 또한, Ingress Controller와 Route53 도메인 연결을 통해 외부 트래픽 유입 경로를 완성합니다.

---

## 2. 아키텍처 및 구성 (Architecture & Configuration)

### A. 리소스 구성
- **ArgoCD**:
  - Helm Chart 기반 설치.
  - "App-of-Apps" 패턴을 통해 루트 애플리케이션(`argocd-root-app`) 배포.
  - OCI Helm Repository (Harbor) 연동 지원.
- **Ingress Controller (Nginx)**:
  - GitOps 리포지토리(`gitops-apps/bootstrap`)에 매니페스트 주입 (.tftpl).
  - AWS NLB (Service Type: LoadBalancer) 자동 프로비저닝.
- **Route53**:
  - 동적으로 생성된 Ingress NLB 엔드포인트를 감지하여 Alias 레코드(A) 생성 (`argocd.*`, `rancher.*`).

### B. 주요 파라미터 (Variables)
| 변수명 | 설정값 (Dev) | 설명 |
|:---|:---|:---|
| `enable_gitops_apps` | `true` | App-of-Apps 패턴 활성화. |
| `argocd_enable_ingress` | `true` | ArgoCD UI를 Ingress로 노출. |
| `use_harbor_oci` | `true` | 인터넷 대신 내부 Harbor를 통해 Helm 차트 설치. |
| `auto_seed_missing_helm_charts` | `true` | 필요 시 로컬에서 Harbor로 차트 미러링 수행. |
| `gitops_repo_url` | `git@github.com...` | GitOps 타겟 리포지토리 주소 (SSH 사용). |

---

## 3. 구현 의도 및 디자인 의사결정 (Design Rationale)

### A. GitOps 'App-of-Apps' 패턴 채택
**설정:**
- `enable_gitops_apps = true`
- `kubectl_manifest.argocd_root_app`

**의도 (Rationale):**
인프라(Terraform)가 애플리케이션의 세세한 설정을 직접 관리하지 않도록 하기 위함입니다.
1.  **Declarative Management**: Terraform은 오직 "ArgoCD"라는 관리 도구 하나만 설치합니다. 이후 Rancher, Cert-Manager, Monitoring 등의 복잡한 앱들은 ArgoCD가 Git 저장소의 상태를 보고 스스로 동기화합니다.
2.  **단일 진실 공급원 (SSOT)**: 클러스터 내 모든 앱의 상태가 Git에 정의되므로, Terraform 재실행 없이도 앱 버전 업그레이드나 설정 변경이 가능합니다.

### B. Ingress 및 인증서의 동적 구성 (Dynamic Ingress & ACM)
**구현 방식:**
- ArgoCD가 Nginx Ingress Controller를 배포하면 AWS NLB가 자동으로 생성됩니다.
- `55-bootstrap` 스택은 이 과정에서 **ACM 인증서를 스스로 탐색(Discovery)**하여 Ingress 설정에 동적으로 주입합니다.

**의도 (Rationale):**
인프라(`50-rke2`)와 애플리케이션(`55-bootstrap`) 간의 의존성을 최소화하기 위함입니다.
1.  **느슨한 결합 (Loose Coupling)**: `50-rke2`가 굳이 인증서 정보를 넘겨주지 않아도, `55-bootstrap`이 독자적으로 필요한 리소스(ACM)를 찾아 연결할 수 있습니다. 이는 스택 간 결합도를 낮춰 운영 유연성을 높여줍니다.
2.  **완전한 파이프라인 자동화**: 인프라 생성부터 도메인 연결까지의 과정이 끊김 없이 이어지도록 하여, `plan` -> `apply` 파이프라인이 실패 없이 한 번에 수행될 수 있도록 보장합니다.

### C. Harbor OCI 레지스트리 기반 Helm 배포
**설정:**
- `use_harbor_oci = true`

**의도 (Rationale):**
폐쇄망(Air-gapped) 환경이나 인터넷 연결이 제한적인 상황을 대비한 설계입니다.
- 인터넷상의 Helm 저장소(charts.bitnami.com 등)에 직접 의존하지 않고, 내부 Harbor OCI 레지스트리를 Proxy 또는 미러로 사용하여 배포 안정성을 확보합니다.
- `auto_seed_missing_helm_charts` 옵션을 통해, 최초 구축 시 로컬 환경에서 필요한 차트를 Harbor로 푸시하는 자동화 로직을 포함하여 운영 편의성을 높였습니다.
