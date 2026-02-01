# 40-Bastion 스택 명세서 (Stack Specification)

## 1. 개요 (Overview)
이 스택은 외부에서 내부 프라이빗 네트워크(Private Subnet)로 접근하기 위한 단일 진입점(Jump Host) 역할을 하는 **Bastion Host**를 생성합니다. 운영자의 관리자 권한 접근 및 터널링을 위한 최소한의 리소스로 구성됩니다.

---

## 2. 아키텍처 및 구성 (Architecture & Configuration)

### A. 리소스 구성
- **EC2 Instance**: `t3.micro` 등 최소 사양. Public Subnet에 배치.
- **Security Group**:
  - 기본적으로 **Inbound 규칙 없음** (SSM 사용 전제).
  - Outbound 전체 허용.
- **IAM Role**: `AmazonSSMManagedInstanceCore` 정책 부착.

### B. 주요 파라미터 (Variables)
| 변수명 | 설정값 (Dev) | 설명 |
|:---|:---|:---|
| `bastion_subnet_key` | `"common-public-a"` | 배포할 서브넷 식별자. |
| `instance_type` | `"t3.small"` | 인스턴스 타입. |
| `iam_policy_arns` | `[]` | 추가 IAM 정책 ARN 목록. |

---

## 3. 구현 의도 및 디자인 의사결정 (Design Rationale)

### A. SSM 기반의 'Keyless' 접근 (`SSM-only`)
**설정:**
- Security Group Inbound 22(SSH) 차단.
- IAM Role에 SSM 관련 권한 부여.

**의도 (Rationale):**
SSH 키 쌍(Key-pair) 관리의 부담과 보안 위험을 원천 제거하기 위함입니다.
- AWS Systems Manager(Session Manager)를 사용하면 SSH 포트를 인터넷에 개방하지 않고도, AWS 인증(IAM)을 통해 안전하게 쉘 접근이 가능합니다.
- `aws-vault` 등을 통해 MFA로 인증된 사용자만 Bastion에 접근할 수 있어 보안성이 크게 향상됩니다.

### B. 최소한의 Jump Host
**설정:**
- `user_data`로 최소한의 부트스트랩만 수행.

**의도 (Rationale):**
Bastion은 그 자체로 업무를 수행하는 곳이 아니라, 단지 **"터널링을 위한 경유지"**일 뿐임을 명확히 합니다.
- Bastion에 불필요한 도구나 데이터를 저장하지 않음으로써, 만약 침해사고가 발생하더라도 공격자가 얻을 수 있는 정보를 최소화합니다.
