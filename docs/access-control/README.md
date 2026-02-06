# Access Control & Security Documentation

이 디렉토리는 Teleport 기반 접근 제어 시스템 및 보안 정책 문서를 포함합니다.

---

## 📚 문서 구조

### 🎯 의사결정 문서
- **[ADR-001: 접근제어 솔루션 선정](ADR-001-access-control-solution.md)**
  - Teleport 선정 배경 및 아키텍처 결정
  - 대안 비교 (AWS Client VPN, Cloudflare Access, Tailscale 등)
  - 멀티클라우드 전략

### 🚀 배포 가이드
- **[Teleport EC2 배포 가이드](teleport-ec2-deployment-guide.md)**
  - **현재 프로젝트 표준** (EC2 기반 All-in-One)
  - 아키텍처, 기술 스택, 배포 절차
  - HA 구성 및 비용 최적화

- **[Teleport 사용자 가이드](teleport-user-guide.md)** ⭐ NEW
  - **일상 사용법 완전 가이드** (개발자/운영자용)
  - tsh 클라이언트 설치 및 로그인
  - SSH/Kubernetes/Database 접속 방법
  - Break-Glass 비상 접근 및 문제 해결

- **[Teleport 프로덕션 가이드](teleport-production-guide.md)**
  - Kubernetes Helm 기반 HA 배포 (대규모 환경용)
  - SSO 통합, 역할 정의, 감사 로그 설정

### 🔐 보안 최적화
- **[보안 최적화 Best Practices](security-optimization-best-practices.md)** ⭐
  - SSH 포트 전략 (Port 22 vs 커스텀 포트)
  - Defense in Depth (계층적 방어)
  - RKE2 보안 강화
  - 멀티클라우드 Break Glass 전략

### 📖 운영 매뉴얼
- **[Teleport 운영 매뉴얼](teleport-operations-manual.md)** ⭐
  - 초기 설정 (관리자 생성, Agent 설정)
  - 일상 사용 (개발자용 tsh 명령어)
  - 관리 작업 (사용자/Role 관리, 세션 관리)
  - 트러블슈팅

---

## 🗂️ Research (연구 자료)

- `research/01-global-solutions.md`: 글로벌 접근 제어 솔루션 비교
- `research/02-korea-trends.md`: 국내 트렌드 및 규제
- `research/03-customer-delivery.md`: 고객사 납품 권장안

---

## 🎯 사용 시나리오별 가이드

| 상황 | 추천 문서 |
|:---|:---|
| **처음 시작** | [ADR-001](ADR-001-access-control-solution.md) → [EC2 배포 가이드](teleport-ec2-deployment-guide.md) |
| **일상 사용** | [사용자 가이드](teleport-user-guide.md) ⭐ |
| **운영 중** | [운영 매뉴얼](teleport-operations-manual.md) |
| **보안 강화** | [보안 최적화](security-optimization-best-practices.md) |
| **대규모 배포** | [프로덕션 가이드](teleport-production-guide.md) |

---

## 📌 핵심 설계 원칙

1. **Zero Trust**: 네트워크는 이미 뚫렸다고 가정
2. **Defense in Depth**: 다층 방어 (Network + Identity + Audit)
3. **Least Privilege**: 최소 권한 부여
4. **Audit Everything**: 모든 접근 기록 및 세션 녹화
5. **Break Glass**: 비상 접근 경로 확보 (AWS SSM)

---

## 🔗 외부 참고 자료

- [Teleport Official Docs](https://goteleport.com/docs/)
- [AWS Security Best Practices](https://docs.aws.amazon.com/security/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
