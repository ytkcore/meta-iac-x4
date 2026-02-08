# [INFRA] Golden Image v2 + 전체 스택 재구조화

## 📋 Summary

전사 EC2 인프라의 OS 이미지를 **Golden Image v2**로 표준화하고,
Terraform 스택 넘버링을 전면 재구조화한다.
VPN 스택을 제거하고, 보안/골든이미지/Teleport/WAF를 새로운 번호 체계로 재배치한다.

## 🎯 Goals

1. **Golden Image 표준화**: Docker, SSM Agent, CloudWatch Agent 사전 설치
2. **스택 재넘버링**: 논리적 의존성 순서에 맞게 재배치
3. **VPN → Teleport 전환**: 15-vpn 제거, 15-teleport으로 교체
4. **WAF 모듈화**: `modules/waf-acl/` 분리 + 20-waf 스택 신설

## 📊 스택 넘버링 변경

```
Before:                          After:
10-security                      05-security        (재넘버링)
15-vpn                           10-golden-image    (신규)
                                 15-teleport        (신규, VPN 대체)
                                 20-waf             (신규)
30-bastion                       30-bastion         (유지)
40-harbor                        40-harbor          (유지)
50-rke2                          50-rke2            (유지)
55-bootstrap                     55-bootstrap       (유지)
60-db                            60-postgres        (분리)
                                 61-neo4j           (분리)
                                 62-opensearch      (분리)
70-observability                 70-observability   (유지)
```

## 📋 Tasks (완료)

### Golden Image v2
- [x] `10-golden-image` 스택 생성 (main.tf, outputs.tf, variables.tf)
- [x] Golden Image outputs: AMI ID, SSH port, component enable 플래그
- [x] `ec2-instance` 공통 모듈 — Golden Image 기본 참조
- [x] 모든 EC2 모듈(harbor, teleport, bastion, rke2)에 Golden Image 연동

### 스택 리팩토링
- [x] `10-security` → `05-security` 이름 변경
- [x] `15-vpn` 제거 (AWS Client VPN 리소스 수동 정리 후)
- [x] `15-teleport` 스택 신규 생성
- [x] `20-waf` 스택 신규 생성 (WAF ACL 모듈 분리)
- [x] 60-db → 60-postgres / 61-neo4j / 62-opensearch 분리
- [x] `config.mk` STACK_ORDER 업데이트

### 모듈 정비
- [x] `modules/waf-acl/` — 재사용 가능한 WAF 모듈
- [x] `modules/teleport-ec2/` — Teleport HA 배포 모듈
- [x] `modules/ec2-instance/` — Golden Image 참조 추가
- [x] 모든 모듈에 Golden Image 변수 전파

## 🔧 주요 변경 파일 (74 files, +6327 -992)

| 범주 | 주요 파일 |
|------|----------|
| Golden Image | `stacks/dev/10-golden-image/`, `modules/ec2-instance/` |
| 스택 이동 | `05-security/`, `15-teleport/`, `20-waf/` |
| 스택 삭제 | `15-vpn/` (VPN 관련 전체 제거) |
| 모듈 신규 | `modules/waf-acl/`, `modules/teleport-ec2/` |
| 문서 | 보안 정책, SSH 운영 정책, VPN 수동 정리 가이드 |
| 스크립트 | `scripts/cleanup/remove-vpn-stack.sh`, `scripts/golden-image/print-summary.sh` |

## 📎 References

- [03-golden-image-strategy.md](../architecture/03-golden-image-strategy.md)
- [Golden Image Specification](../infrastructure/golden-image-specification.md)
- [VPN 수동 정리 가이드](../troubleshooting/client-vpn-manual-cleanup.md)

## 🏷️ Labels

`golden-image`, `stack-restructure`, `vpn-removal`, `waf`, `teleport`

## 📌 Priority / Status

**Critical** / ✅ 완료 (2026-02-04)
