# 00-Network 스택 명세서 (Stack Specification)

## 1. 개요 (Overview)
이 스택은 전체 인프라의 근간이 되는 VPC(Virtual Private Cloud) 환경을 구성합니다. 서브넷, 라우팅 테이블, 인터넷/NAT 게이트웨이 등 기본 네트워크 토폴로지를 정의하며, S3/DynamoDB 접근을 위한 Gateway Endpoint를 포함합니다.

---

## 2. 아키텍처 및 구성 (Architecture & Configuration)

### A. 리소스 구성
- **VPC**: 지정된 CIDR 대역으로 격리된 네트워크 공간 생성.
- **Subnets**: 3-Tier 아키텍처 (Public / Private / DB).
  - `public`: IGW를 통해 인터넷 직접 접근 가능.
  - `private`: NAT Gateway를 통해 아웃바운드 인터넷 접근 가능.
  - `db`: 기본적으로 외부 통신 차단 (옵션으로 NAT 연결 가능).
- **Gateways**:
  - `igw`: 인터넷 게이트웨이 (Public Subnet용).
  - `nat`: NAT 게이트웨이 (Private Subnet용, AZ별 생성 가능).
- **VPC Endpoint (Gateway Type)**: S3 및 DynamoDB용 무료 엔드포인트 자동 생성.

### B. 주요 파라미터 (Variables)
| 변수명 | 설정값 (예시) | 설명 |
|:---|:---|:---|
| `vpc_cidr` | `10.0.0.0/16` | VPC 전체 IP 대역. |
| `enable_nat` | `true` | NAT Gateway 생성 여부 (Private Subnet 인터넷 연결용). |
| `enable_gateway_endpoints` | `true` | S3/DynamoDB Gateway Endpoint 생성 여부. |
| `subnets` (Map) | `{ zone-a = { cidr=..., tier="public" } }` | 서브넷 정의 (CIDR, AZ, Tier). |

---

## 3. 구현 의도 및 디자인 의사결정 (Design Rationale)

### A. Gateway Endpoint의 `00-network` 배치
**설정:**
- `resource "aws_vpc_endpoint" "gateway"` 포함

**의도 (Rationale):**
Gateway Endpoint(S3, DynamoDB)는 사용료가 무료이며 대역폭 제한이 없고, 라우팅 테이블 레벨에서 제어되므로 "기본 네트워크 인프라"의 일부로 보는 것이 타당합니다.
- 반면 Interface Endpoint(SSM 등)는 시간당 과금이 발생하므로 `20-endpoints`로 분리하여 비용/필요성에 따라 선택적으로 배포하게 했습니다.

### B. DB Tier와 NAT의 분리
**설정:**
- `enable_nat_for_db` (기본 `false`)

**의도 (Rationale):**
데이터베이스 서브넷(`db`)은 보안상 외부와의 연결을 완전히 차단하는 것이 원칙입니다.
- 그러나 RDS 유지보수나 외부 패치 다운로드가 필요한 예외 상황을 대비하여, `enable_nat_for_db` 옵션만 켜면 라우팅 테이블을 수정해 NAT를 탈 수 있도록 유연성을 열어두었습니다.

### C. Terraform 모듈화 구조
**의도 (Rationale):**
`modules/vpc`, `modules/subnets` 등으로 잘게 쪼개져 있습니다. 이는 네트워크 변경(특히 서브넷 CIDR 변경 등)이 전체 인프라에 치명적인 영향을 주기 때문에, 각 컴포넌트의 변경 영향도를 최소화하고 재사용성을 높이기 위함입니다.
