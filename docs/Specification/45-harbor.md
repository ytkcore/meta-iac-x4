# 45-Harbor 스택 명세서 (Stack Specification)

## 1. 개요 (Overview)
이 스택은 컨테이너 이미지 및 Helm 차트 저장소 역할을 하는 **Harbor Registry**를 단일 EC2 인스턴스에 구축합니다. 외부 인터넷이 차단된 환경(Air-gapped)에서도 Kubernetes 클러스터가 이미지를 가져오고(Pull), Helm 차트를 설치할 수 있도록 지원하는 핵심 컴포넌트입니다.

---

## 2. 아키텍처 및 구성 (Architecture & Configuration)

### A. 리소스 구성
- **EC2 Instance**: Docker 및 Docker Compose 기반의 Harbor 실행.
- **ALB (Application Load Balancer)**: HTTPS(443) 트래픽 수신 및 SSL Termination.
- **S3 Bucket**: Docker 이미지 레이어 및 차트 데이터의 영구 저장소.
- **Route53**: `harbor.{domain}` 레코드(CNAME) 생성.

### B. 주요 파라미터 (Variables)
| 변수명 | 설정값 (Dev) | 설명 |
|:---|:---|:---|
| `create_proxy_cache` | `true` | DockerHub 등 외부 레지스트리 프록시 프로젝트 생성. |
| `helm_seeding_mode` | `"user-data" or "local-exec"` | Helm 차트 초기 적재 방식. |
| `seed_images` | `[...]` | 초기 부팅 시 미리 Pull 받아올 이미지 목록. |

---

## 3. 구현 의도 및 디자인 의사결정 (Design Rationale)

### A. 폐쇄망 지원을 위한 'Self-contained' 전략
**설정:**
- `enable_proxy_cache = true`
- `seed_helm_charts = true`

**의도 (Rationale):**
인터넷 연결이 불안정하거나 보안상 차단된 환경에서도 클러스터 부트스트래핑(RKE2, ArgoCD 설치)이 가능해야 합니다.
- **Helm Seeding**: ArgoCD, Cert-Manager, Rancher 등 필수 차트를 Harbor 내 OCI 레지스트리에 미리 적재함으로써, 이후 단계인 `55-bootstrap`이 외부 인터넷 없이도 설치를 진행할 수 있게 합니다.
- **Proxy Cache**: DockerHub, Quay.io 등에 대한 프록시 프로젝트를 구성하여, 한 번 다운로드된 이미지는 로컬에 캐싱되므로 잦은 Pull로 인한 스로틀링(Rate Limit)을 방지하고 배포 속도를 높입니다.

### B. S3 백엔드 스토리지 사용
**설정:**
- `storage_type = "s3"`

**의도 (Rationale):**
EC2 인스턴스(EBS)에 데이터를 저장할 경우, 인스턴스 장애나 재생성 시 데이터 유실 위험이 크고 용량 확장이 어렵습니다.
- 데이터의 영속성(Persistence)과 무제한에 가까운 확장성을 보장하기 위해 이미지 데이터를 S3 버킷에 저장하도록 설계했습니다. 이를 통해 Harbor 인스턴스 자체는 `Stateless`에 가깝게 관리될 수 있어 복구가 용이합니다.
