# 프로젝트 표준 가이드 (Project Standards Guide)

본 문서는 프로젝트 진행 간 모든 참여자가 준수해야 할 **커뮤니케이션**, **문서화**, 그리고 **아키텍처 고도화**에 대한 원칙을 정의합니다.

---

## 1. 커뮤니케이션 및 문서화 표준 (Communication Standards)

### 1.1 기본 원칙 (Core Principles)

1.  **언어 (Language)**:
    - **모든 커뮤니케이션은 한국어를 기본으로 합니다.** (Korean First Policy)
    - 기술적인 정확성을 위해 영문 용어(예: Kubernetes, Ingress, Pod)는 원어로 표기할 수 있으나, 문맥과 설명은 반드시 한국어로 작성합니다.

2.  **문서화 (Documentation)**:
    - 아키텍처 문서, 트러블슈팅 가이드, 운영 매뉴얼 등 모든 산출물은 **한글로 작성**되어야 합니다.
    - Jira 티켓의 요약, 설명, 댓글 또한 한글 작성을 원칙으로 합니다.

3.  **코드 주석 (Code Comments)**:
    - 코드 내 주석은 가독성을 위해 영문을 허용하나, 복잡한 로직이나 중요 정책 설명은 한글로 부연하는 것을 권장합니다.
    - 단, 파일 헤더(File Header) 등의 템플릿화된 주석은 기존 영문 컨벤션을 따를 수 있습니다.

### 1.2 적용 범위 (Scope)

본 표준은 다음 항목에 적용됩니다:

- **Jira / Issue Tracker**: 티켓 생성, 상태 업데이트, 완료 보고.
- **Git Commit Message**: (선택 사항이나, PR 본문 및 설명은 한글 권장)
- **Technical Documentation**: `docs/` 디렉토리 내의 모든 문서.
- **Troubleshooting Guide**: 장애 분석 및 해결 과정 보고서.
- **Real-time Communication**: 채팅, 회의 등.

### 1.3 작업 절차 표준 (Work Process Standards)

1.  **선(先) 실행계획 보고, 후(後) 작업 착수 (Plan First, Act Later)**:
    - 단순 완결성 중심의 요청(예: 오타 수정, 명백한 버그 픽스)을 제외한 모든 작업은 **실행 계획(Implementation Plan)**을 먼저 작성하여 사용자에게 보고해야 합니다.
    - 사용자의 **명시적인 승인(Approval)**이 있기 전까지는 실제 코드 변경이나 명령어 실행을 진행하지 않습니다.
    - 계획 보고 시에는 목표, 변경 대상 파일, 위험 요소, 검증 방법을 명확히 기술합니다.

---

## 2. 아키텍처 고도화 점검 지침

### 2.1 핵심 원칙

고도화 작업 진행 시, **새로운 컴포넌트 추가 또는 기존 인프라 변경이 발생할 때마다** 다음을 반드시 수행한다:

#### 1. 기존 로드맵 재평가 (Impact Re-Assessment)
- 새 컴포넌트(예: Vault, Cilium) 도입 후, **기존 미결 항목(Phase 3 등)이 영향을 받는지 재분석**
- "기존 문서의 결정 사항을 그대로 반복"하지 않고, **변경된 스택을 반영한 최선책을 재탐색**
- 예시: Vault K8s auth 구축 완료 → Phase 3 IRSA를 S3 OIDC 대신 Vault AWS Secrets Engine으로 전환 가능성 분석

#### 2. 글로벌 업계 표준 + 국내 베스트 프랙티스 참조
- 매 의사결정 시 **글로벌 업계 표준**(CNCF, AWS Well-Architected, HashiCorp best practices)과 **국내 실 사례**(대규모 K8s 운영 기업)를 함께 참고
- 단순히 "동작하는 방식"이 아니라, **장기 운영 관점에서 최적인 방식**을 선택
- "이미 결정된 사항"이라도 환경이 변했다면 **재검토가 의무**

#### 3. 변화 수용 환경 고려
- CSP 종속 최소화 (Bridge 전략 일관성)
- 수동 관리 오버헤드 최소화 (자동화 가능한 방식 우선)
- 초기 구축 시 베스트 아키텍처를 최대한 완성 (나중에 고치는 비용 >> 처음 잘 하는 비용)

#### 4. 점검 트리거
다음 상황에서 반드시 위 1~3을 수행:
- 새 컴포넌트 ArgoCD 앱 추가 시
- Terraform 모듈 신규 생성/대규모 변경 시
- 아키텍처 문서 업데이트 시
- 미결 Phase 착수 전

### 2.2 사이드이펙트 / 잠재 리스크 사전 점검 (필수)

**모든 개선 작업(설정 변경, 모듈 수정, 서비스 업그레이드, 코드 리팩토링 등)을 수행하기 전에, 반드시 다음을 선행한다:**

1. **전체 아키텍처 영향도 분석**
   - 변경 대상이 참조되는 모든 Terraform `remote_state`, Helm values, Ingress, NetworkPolicy, CiliumNetworkPolicy를 `grep_search`로 추적
   - 14개 스택(00-network ~ 80-access-gateway) 간 의존성 체인을 확인하고, 변경이 전파될 수 있는 하위 스택을 식별

2. **구현된 소스코드 레벨 점검**
   - 변경 대상의 변수명, output명, 리소스명이 다른 파일에서 참조되는지 확인
   - GitOps 앱(gitops-apps/) 내 Helm values에서 하드코딩된 값(IP, 도메인, Secret명 등)이 영향받는지 확인
   - Keycloak SSO 연동(client_id, client_secret, redirect_uri)이 영향받는 변경인지 확인

3. **잠재 리스크 명시적 보고**
   - 발견된 사이드이펙트나 잠재 리스크가 있으면, 코드 변경 전에 사용자에게 **먼저 보고**
   - "이 변경은 X, Y 서비스에 영향을 줄 수 있습니다" 형태로 구체적으로 전달
   - 리스크가 없다고 판단되더라도, 점검을 수행했음을 간략히 언급

4. **롤백 가능성 확보**
   - Terraform 변경 시 `destroy/recreate`가 발생하는 리소스가 있으면 반드시 경고

---

## 3. 관련 컨벤션 및 문서 (References)

본 표준 가이드와 함께 다음의 세부 컨벤션 문서를 반드시 참고하고 준수해야 합니다.

| 구분 | 문서명 | 주요 내용 |
|:---|:---|:---|
| **네이밍** | [`01-naming-convention.md`](./01-naming-convention.md) | AWS 리소스 및 Terraform 모듈 명명 규칙 표준 |
| **운영** | [`post-deployment-operations-guide.md`](../guides/post-deployment-operations-guide.md) | 구축 후 필수 운영 가이드 및 초기 설정 절차 |
| **온보딩** | [`web-service-onboarding.md`](../guides/web-service-onboarding.md) | 신규 웹 서비스 배포 및 인프라 연동 표준 |
| **보안/접근** | [`security-optimization-best-practices.md`](../access-control/security-optimization-best-practices.md) | 보안 최적화 및 접근 제어 정책 |

