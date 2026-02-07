# [INFRA] Internal NLB 수동 Target 등록 자동화 — CCM Bug 임시 해결

## 📋 Summary

AWS CCM이 NLB Target Group에 Worker Node를 자동 등록하지 못하는 버그에 대한 임시 해결.
현재 수동 등록된 Target은 Worker Node 변경 시 재등록이 필요하므로, Lambda 또는 스크립트 기반 자동화를 구현한다.

## 🎯 Goals

1. Worker Node 변경 시 자동 Target 등록/해제
2. 수동 운영 부채 최소화 (ALBC 도입 전까지)
3. Target Health 모니터링

## 📊 현재 상태

| 항목 | 상태 |
|------|------|
| Internal NLB | `ac0b9c624...` (Helm 생성) |
| HTTPS TG | 4 Workers × Port 32081 (수동 등록) |
| HTTP TG | 4 Workers × Port 32419 (수동 등록) |
| Target Health | 8/8 healthy ✅ |
| 자동화 | ❌ 없음 |

## 📋 Tasks

### Option A: EventBridge + Lambda (권장)

- [ ] **A.1** Lambda 함수 생성
  - EC2 Instance StateChange 이벤트 감지
  - ASG 태그 기반 Worker 식별
  - Target Group 자동 등록/해제
- [ ] **A.2** EventBridge Rule 생성
  - `EC2 Instance State-change: running/terminated`
- [ ] **A.3** IAM Role (Lambda용) 생성
- [ ] **A.4** CloudWatch Alarm (TG unhealthy 시 SNS 알림)

### Option B: CronJob 스크립트 (간단)

- [ ] **B.1** 스크립트 작성 (현재 Worker 목록 ↔ TG Target 동기화)
- [ ] **B.2** Master Node에 cron 등록 (5분 주기)
- [ ] **B.3** 로그 수집 설정

## ⚠️ Notes

- ALBC 도입 시 이 자동화는 **폐기** 예정
- Option A가 이벤트 기반이므로 더 반응성이 높음
- Option B가 구현이 간단하나, 최대 5분 지연

## 🔗 관련 티켓

- [ALBC 도입](albc-adoption.md) — 이 티켓의 근본 해결책
- [Teleport App Access 트러블슈팅](../troubleshooting/teleport-app-access-internal-nlb.md)
