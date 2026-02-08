# [INFRA] 인프라 복원력 강화 — Destroy 자동화 + Remote State Resilience

## 📋 Summary

전체 인프라의 `make destroy-all` 100% 자동 삭제를 달성하기 위해,
스크립트 모듈화, Remote State `try()` 패턴 전수 적용, DNS Hygiene 자동화를 수행한다.

## 🎯 Goals

1. **`make destroy-all`**: 수동 개입 없는 100% 자동 삭제
2. **Remote State Resilience**: 스택 삭제 순서에 상관없는 완결성
3. **DNS Hygiene**: Ingress 삭제 전 DNS 정리, 고아 TXT 레코드 자동 제거
4. **Private DNS 자동화**: VPC 전용 Route53 Private Hosted Zone 자동 생성

## 📊 해결 대상

| 문제 | 원인 | 해결 |
|------|------|------|
| `make destroy` 실패 | SG 순환 참조 + ENI 잔존 | `pre-destroy-hook.sh` 정밀 타격 |
| 스택 삭제 순서 의존성 | Remote State 참조 실패 | `try()` + `coalesce()` 전수 적용 |
| Webhook 차단 에러 | K8s 리소스 삭제 시 웹훅 서버 부재 | Finalizer 자동 제거 |
| 고아 DNS 레코드 | 서비스 삭제 후 TXT 레코드 잔존 | 자동 탐지 + 삭제 |

## 📋 Tasks (완료)

### 스크립트 모듈화
- [x] `pre-destroy-hook.sh` — 함수별 리팩토링
- [x] `force-cleanup.sh` — 고아 리소스 강제 정리
- [x] `scripts/terraform/destroy-all.sh` — 전체 삭제 자동화

### Remote State Resilience
- [x] 전체 스택(00~70) Remote State 참조부 `try()` 패턴 적용
- [x] `coalesce()` 패턴으로 기본값 안전 처리
- [x] 테스트: 임의 스택 삭제 후 타 스택 `plan` 정상 확인

### DNS Hygiene
- [x] Graceful DNS Flush — Ingress 삭제 전 DNS 레코드 선제 삭제
- [x] 고아 TXT 레코드 자동 탐지 + 삭제 로직
- [x] Private Hosted Zone 자동 생성 (00-network)
- [x] DB(PostgreSQL, Neo4j) Private DNS A 레코드 자동 생성

### K8s 리소스 정리
- [x] Stuck Namespace Finalizer 자동 제거
- [x] Webhook 부재 시 삭제 명령 거부 해결

### Bastion 최적화
- [x] 공인 IP(EIP) 제거 → SSM 기반 Private Jump Server
- [x] `ec2-instance` 공용 모듈 + Golden Image 기반 표준화

## 📊 검증 결과

```
$ make destroy-all
  00-network → 05-security → 10-golden-image → ... → 70-observability
  ✅ 전체 삭제 성공 (수동 개입 0회)
```

## 🔧 주요 변경 파일

| 파일 | 작업 |
|------|------|
| `scripts/terraform/pre-destroy-hook.sh` | ✏️ 함수 리팩토링 |
| `scripts/terraform/force-cleanup.sh` | ✏️ 고아 리소스 정리 |
| `scripts/terraform/destroy-all.sh` | 🆕 전체 삭제 스크립트 |
| `stacks/dev/*/main.tf` | ✏️ `try()` 패턴 전수 적용 |
| `stacks/dev/00-network/main.tf` | ✏️ Private Hosted Zone |

## 📎 References

- [terraform-destroy-provisioner-limit.md](../troubleshooting/terraform-destroy-provisioner-limit.md)
- [2026-02-02-infra-foundation-tickets.md](2026-02-02-infra-foundation-tickets.md) — INFRA-003 관련

## 🏷️ Labels

`resilience`, `destroy`, `automation`, `dns-hygiene`

## 📌 Priority / Status

**High** / ✅ 완료 (2026-02-02)
