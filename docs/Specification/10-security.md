# 10-Security 스택 명세서 (Stack Specification)

## 1. 개요 (Overview)
이 스택은 인프라 전반에서 사용되는 **공통 보안 그룹(Security Groups)**을 중앙 집중적으로 관리합니다. VPC 생성(`00-network`) 직후에 실행되어, 이후 배포될 애플리케이션, 데이터베이스, 로드밸런서가 즉시 참조할 수 있는 보안 규칙을 제공합니다.

---

## 2. 아키텍처 및 구성 (Architecture & Configuration)

### A. 리소스 구성
- **ALB Security Group**: 외부 트래픽(HTTP/HTTPS) 수신용.
- **Internal LB Security Group**: 내부 마이크로서비스 간 통신용.
- **Bastion Security Group**: 관리자 접속용 (SSH).
- **Common Rules**:
  - 관리자 네트워크(`admin_cidrs`)에서의 접근 허용.
  - 로드밸런서 -> 워커 노드 간의 트래픽 라우팅 허용.

### B. 주요 파라미터 (Variables)
| 변수명 | 설정값 (예시) | 설명 |
|:---|:---|:---|
| `admin_cidrs` | `["1.2.3.4/32"]` | 관리자(오피스/VPN) IP 대역. |
| `lb_ingress_cidrs` | `["0.0.0.0/0"]` | Public LB 접근 허용 대역 (기본 전체). |
| `allow_db_from_bastion` | `true` | Bastion 호스트에서 DB 포트 접근 허용 여부. |

---

## 3. 구현 의도 및 디자인 의사결정 (Design Rationale)

### A. 보안 그룹의 중앙 집중화
**설정:**
- 모든 SG를 `10-security`에서 생성하고, 타 스택(`50-rke2`, `60-db`)은 이를 `data "terraform_remote_state"`로 참조.

**의도 (Rationale):**
"순환 의존성(Circular Dependency)"을 방지하고 보안 정책의 가시성을 높이기 위함입니다.
- 예를 들어, 앱과 DB가 서로의 SG를 참조해야 하는 경우, 동일한 스택에 있으면 상호 참조 에러가 발생하기 쉽습니다.
- 보안 그룹을 먼저 생성해 두면, 이후 스택들은 단순히 ID만 가져다 쓰면 되므로 의존성 관리가 단순해집니다.
- 또한, 보안 감사 시 `10-security` 스택만 확인하면 전체 인바운드/아웃바운드 정책을 파악할 수 있습니다.

### B. 규칙의 추상화 (Abstraction)
**설정:**
- `enable_nodeport_from_lb`

**의도 (Rationale):**
개별 포트(80, 443, 30000...)를 일일이 하드코딩하는 대신, "LB에서 노드로의 접근을 허용한다"는 **의도(Intent)** 기반의 변수를 사용했습니다.
- 이는 k8s NodePort 범위 변경이나 프로토콜 변경 시에도 사용자 실수 없이 안전하게 규칙을 업데이트할 수 있게 합니다.
