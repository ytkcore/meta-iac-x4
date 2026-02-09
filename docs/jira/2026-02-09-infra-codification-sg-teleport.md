# [INFRA] 형상 관리 정합성 — SG 코드화 + Teleport 앱 동적 렌더링

## 📋 Summary

수동으로 적용된 NLB Security Group 규칙을 **Terraform 코드로 정식 편입**하고,
Teleport 앱 등록 시 **`rewrite_redirect` 필드가 type 정의 누락**으로 무시되던 문제를 수정.

## 🎯 Goals

1. **SG 규칙 IaC 전환**: AWS CLI 수동 추가 → Terraform `aws_security_group_rule`
2. **Teleport 앱 type 정합성**: `rewrite_redirect` 필드가 정상 전달되도록 type 보완
3. **Observability 앱 등록**: Alertmanager, Prometheus를 Teleport App Access에 추가

## 📋 Tasks

- [x] **T3** `80-access-gateway/variables.tf` — `kubernetes_services` type에 `rewrite_redirect` 추가
- [x] **T4** `50-rke2/main.tf` — `aws_security_group_rule` (80/443, `0.0.0.0/0`) 추가
- [x] **추가** `80-access-gateway/variables.tf` — alertmanager, prometheus 앱 등록

## 🔧 변경 파일

| 파일 | 변경 |
|------|------|
| `stacks/dev/50-rke2/main.tf` | `aws_security_group_rule` nlb_public_http/https 추가 |
| `stacks/dev/80-access-gateway/variables.tf` | `rewrite_redirect` type 추가 + alertmanager/prometheus |

## 📎 Commits

| Hash | 설명 |
|------|------|
| `631656d` | SG 코드화 + rewrite_redirect type 수정 |
| `2df51cd` | Alertmanager, Prometheus Teleport 등록 |

## ⚠️ 주의사항

- `50-rke2`: 기존 수동 SG 규칙과 충돌 가능 → `terraform import` 필요할 수 있음
- `80-access-gateway`: `terraform apply` 후 Teleport EC2에 SSM으로 앱 설정 반영

## 🏷️ Labels

`terraform`, `security-group`, `teleport`, `infrastructure-codification`

## 📌 Priority / Status

**High** | ✅ **Done** (코드 완료, apply 대기)
