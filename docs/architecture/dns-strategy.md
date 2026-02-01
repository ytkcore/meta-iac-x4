# DNS Architecture & Strategy

**작성일**: 2026-02-01  
**관련 컴포넌트**: Route53, ExternalDNS, Ingress Controller

---

## 1. 개요 (Overview)
본 프로젝트는 **Hybrid DNS Management** 전략을 사용합니다.
- **Terraform**: Route53 Hosted Zone 생성 및 영구적인 인프라성 레코드 관리.
- **ExternalDNS**: Kubernetes Ingress/Service 리소스에 기반한 동적 레코드 자동 관리.

## 2. 도메인 구조 (Domain Structure)
| 도메인 | 레코드 유형 | 관리 주체 | 설명 |
| :--- | :--- | :--- | :--- |
| **`unifiedmeta.net`** | NS / SOA | Terraform | Root Hosted Zone |
| **`argocd.unifiedmeta.net`** | A (Alias) | ExternalDNS | ArgoCD 접속 주소 (ALB/CLB 연결) |
| **`rancher.unifiedmeta.net`** | A (Alias) | ExternalDNS | Rancher 접속 주소 |
| **`harbor.unifiedmeta.net`** | CNAME | Terraform | Harbor OCI Registry (별도 ALB 사용) |
| **`_acme-challenge...`** | CNAME | Cert-Manager | SSL 인증서 발급을 위한 검증 레코드 |

---

## 3. ExternalDNS 동작 방식 (TXT Registry)
Route53을 보면 `argocd.unifiedmeta.net` 외에도 `a-argocd...` 같은 TXT 레코드가 존재합니다. 이는 **ExternalDNS의 소유권 관리 메커니즘**입니다.

### 3.1. 레코드 유형별 역할
1.  **A 레코드 (Alias)**
    *   **용도**: 실제 트래픽이 흐르는 주소.
    *   **대상**: 사용자 접근용.
    *   **값**: `afb...elb.amazonaws.com` (AWS 리소스)

2.  **TXT 레코드 (Registry)**
    *   **용도**: ExternalDNS가 해당 도메인의 **소유권(Ownership)** 을 주장하고 관리하기 위한 메타데이터.
    *   **대상**: 시스템 내부용 (삭제 금지).
    *   **구조**:
        *   `a-<domain>`: A 레코드에 대한 소유권 마킹.
        *   `cname-<domain>`: CNAME 레코드에 대한 소유권 마킹.
    *   **값 예시**:
        ```text
        "heritage=external-dns,external-dns/owner=external-dns-bootstrap,external-dns/resource=ingress/argocd/argocd-server"
        ```
        *   `owner`: 레코드를 생성한 컨트롤러 ID (예: `external-dns-bootstrap`). 다른 ExternalDNS 인스턴스가 이 레코드를 덮어쓰지 못하도록 방지.
        *   `resource`: K8s 내부의 원본 리소스 위치.

### 3.2. 주의사항
*   **수동 수정 금지**: Route53 콘솔에서 이 TXT 레코드를 임의로 삭제하거나 수정하면, ExternalDNS는 해당 도메인의 소유권을 잃어버렸다고 판단하여 레코드 업데이트를 중단하거나 재생성하려 시도할 수 있습니다.
*   **충돌 방지**: 동일한 도메인을 여러 클러스터(Dev/Prod)에서 사용하려 할 때, 이 TXT 레코드가 락(Lock) 역할을 하여 의도치 않은 덮어쓰기를 방지합니다.
