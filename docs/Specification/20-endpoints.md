# 20-Endpoints 스택 명세서 (Stack Specification)

## 1. 개요 (Overview)
이 스택은 AWS 서비스(SSM, EC2 등)에 대한 **VPC Interface Endpoint**를 관리합니다. Private Subnet에 위치한 인스턴스들이 인터넷(NAT Gateway)을 거치지 않고 AWS 내부망을 통해 안전하고 빠르게 서비스에 접근할 수 있도록 경로를 제공합니다.

---

## 2. 아키텍처 및 구성 (Architecture & Configuration)

### A. 리소스 구성
- **Interface VPC Endpoints**: 지원되는 각 AWS 서비스별로 ENI(Elastic Network Interface) 생성.
  - `ssm`, `ssmmessages`, `ec2messages`: AWS Systems Manager (Session Manager) 접속용 필수.
  - `ec2`: EC2 API 호출용.
- **Security Group**: 엔드포인트에 대한 VPC 내부 접근(HTTPS 443) 허용.

### B. 주요 파라미터 (Variables)
| 변수명 | 설정값 (예시) | 설명 |
|:---|:---|:---|
| `enable_interface_endpoints` | `true` | 인터페이스 엔드포인트 생성 활성화 여부. |
| `interface_services` | `["ssm", "ec2", ...]` | 생성할 서비스 목록. |
| `interface_subnet_tiers` | `["private"]` | 엔드포인트를 배치할 서브넷 티어. |

---

## 3. 구현 의도 및 디자인 의사결정 (Design Rationale)

### A. `00-network`와의 스택 분리
**설정:**
- 별도의 State 파일 (`20-endpoints.tfstate`)

**의도 (Rationale):**
**비용 통제(Cost Control)와 변경 격리**를 위함입니다.
- Gateway Endpoint(S3)는 무료지만, Interface Endpoint는 시간당 과금 + 데이터 처리 비용이 발생합니다.
- 개발/테스트 환경에서 비용 절감을 위해 NAT Gateway만 남기고 엔드포인트를 제거하거나, 반대로 보안 강화(PrivateLink)가 필요할 때 VPC 자체를 건드리지 않고 Endpoint만 손쉽게 On/Off 할 수 있도록 독립 스택으로 분리했습니다.

### B. Systems Manager(SSM) 필수 구성
**설정:**
- `ssm`, `ssmmessages`, `ec2messages` 포함

**의도 (Rationale):**
Bastion 호스트나 RKE2 노드에 **SSH 포트(22)를 개방하지 않고도** 안전하게 터미널 접근을 지원하기 위함입니다.
- 프라이빗 서브넷의 인스턴스가 인터넷 연결 없이도 AWS Systems Manager와 통신하려면 이 엔드포인트들이 필수적입니다.
