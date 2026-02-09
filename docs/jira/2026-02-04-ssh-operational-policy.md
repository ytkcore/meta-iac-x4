# SSH 운영 정책 표준화 수립

> **Status**: ✅ 완료  
> **Priority**: High  
> **Labels**: `security`, `ssh`, `access-control`, `policy`  
> **적용일**: 2026-02-04  
> **커밋**: `63afa64` — `added teleport`

---

## 📋 요약

SSH 접근 제어에 대한 **운영 정책 표준**을 수립하고 문서화한다.
Teleport + SSM + Direct SSH의 3단계 Hybrid Access Pattern을 정의하고,
Golden Image 통합, 스택별 정책, Break-Glass 절차, 포트 정책, 감사/컴플라이언스까지
포괄하는 종합 SSH 운영 표준을 확립한다.

---

## 🎯 목표

1. SSH 접근 방법 우선순위 정의 (Teleport → SSM → Direct SSH)
2. 스택별 SSH 활성화 매트릭스 수립 (05-security ~ 60-db)
3. Golden Image 포트 전략 확립 (Port 22 기본 유지, 배포 시 동적 변경)
4. Break-Glass 비상 접근 절차 표준화
5. 글로벌 기업 벤치마킹 기반 포트 정책 가이드 제공
6. 감사 로그 및 컴플라이언스 요구사항 정의

---

## 📂 산출물

| 파일 | 내용 | 분량 |
|:-----|:-----|:-----|
| [`ssh-operational-policy.md`](../security/ssh-operational-policy.md) | SSH 전용 운영 정책 (포트, Break-Glass, 스택별 정책) | ~800줄 |
| [`comprehensive-security-policy.md`](../security/comprehensive-security-policy.md) | 종합 보안 정책 (SSH 포함 전체 보안 표준) | ~624줄 |
| [`security-optimization-best-practices.md`](../access-control/security-optimization-best-practices.md) | 보안 최적화 베스트 프랙티스 | 가이드 |

---

## ✅ 작업 내역

### Phase 1: 정책 수립 (2/4)

- [x] **1.1** 글로벌 기업 SSH 운영 벤치마킹 (FAANG, 금융권, 공공기관)
- [x] **1.2** 3단계 Hybrid Access Pattern 설계 (Teleport → SSM → Direct SSH)
- [x] **1.3** 5-Layer 보안 계층 구조 설계 (Physical → Network → Identity → Authorization → Audit)
- [x] **1.4** 스택별 SSH 활성화 매트릭스 정의

### Phase 2: 포트 정책 (2/4)

- [x] **2.1** Golden Image 포트 전략 수립 — Port 22 기본 유지, 배포 시 `ssh_port` 변수로 동적 변경
- [x] **2.2** 환경별 포트 가이드 (Dev: 22, Enterprise: 22022, SMB: 22)
- [x] **2.3** `make init` 워크플로우 설계 — SSH 포트 선택 프롬프트 + `env.tfvars` 자동 생성

### Phase 3: 운영 절차 (2/4)

- [x] **3.1** Break-Glass 절차 표준화 (Jira 티켓 → 임시 SG → 작업 → SG 제거)
- [x] **3.2** Golden Image 통합 — user-data.sh 포트 변경, Teleport Agent 자동 등록
- [x] **3.3** 감사 요구사항 정의 (Teleport 세션 녹화, CloudTrail, CloudWatch)
- [x] **3.4** 고객 납품 가이드라인 (엔터프라이즈 vs SMB 분리)

---

## 🔑 핵심 정책 요약

### 접근 우선순위

| 순위 | 방법 | 대상 | 감사 |
|:---:|:-----|:-----|:-----|
| 1순위 | **Teleport SSH** | EC2 (Agent 설치) | ✅ 세션 녹화 |
| 2순위 | **AWS SSM** | 모든 EC2 | ✅ CloudTrail |
| 3순위 | **Direct SSH** | EC2 (긴급) | ⚠️ CloudWatch |

### 스택별 SSH 정책

| 스택 | SSH SG | Teleport Agent | 접근 방법 |
|:-----|:------:|:--------------:|:----------|
| **15-teleport** | ❌ 차단 | ✅ 자체 | SSM Only |
| **30-bastion** | ❌ 차단 | ✅ 설치 | Teleport / SSM |
| **40-harbor** | ❌ 차단 | ✅ 설치 | Teleport / SSM |
| **50-rke2** | ⚠️ Optional | ❌ (Pod) | SSM / Kube Agent |
| **60-db** | ❌ 차단 | ✅ 설치 | Teleport / SSM |

### 포트 전략

```
Golden Image 기본값: Port 22 (표준)
  ↓ 배포 시 ssh_port 변수로 동적 변경
  ↓ user-data.sh → sshd_config Port 변경
  ↓ SSM은 포트 무관 → Break-Glass 안전
```

---

## 🔗 관련 티켓

- [teleport-ha-access-control](2026-02-04-teleport-ha-access-control.md) — Teleport HA 배포 (동일 날짜)
- [teleport-kube-agent-pod](2026-02-04-teleport-kube-agent-pod.md) — Kube Agent Pod 배포
- [golden-image-restructure](2026-02-04-golden-image-stack-restructure.md) — Golden Image v2 전환
- [infra-codification-sg-teleport](2026-02-09-infra-codification-sg-teleport.md) — SG 코드화

---

## 📝 비고

- 이전 대화(`4b6e97ee`)에서 SSH 정책 정제 및 표준화 작업 수행
- 포트 변경은 **Golden Image 빌드 시 고정이 아닌**, 배포 시점에 동적으로 결정하는 전략 채택
- Break-Glass 절차는 Jira 기반 승인 + 임시 SG + 30분 타임아웃 + 자동 제거로 설계
