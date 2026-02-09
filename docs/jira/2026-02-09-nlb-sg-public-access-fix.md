# [INFRA] NLB IP-mode Security Group 외부 접근 수정

## 📋 Summary

Internet-facing NLB가 IP-mode로 동작 시 client source IP를 preserve하므로,
Worker 노드 SG(`dev-meta-k8s-common-sg`)에 `0.0.0.0/0` inbound 규칙이 필요.
기존에는 VPC CIDR(`10.0.0.0/16`)만 허용하여 외부 접근이 차단되고 있었음.

## 🎯 Root Cause

```
Client (Public IP) → NLB (IP-mode, source IP preserve) → Worker Node:NodePort
                                                          └─ SG: 10.0.0.0/16 only ❌
```

NLB Instance-mode는 NLB 자체가 source IP를 변환하므로 VPC CIDR만으로 충분하지만,
**IP-mode**는 client source IP를 그대로 전달하므로 public IP 대역 허용이 필수.

## 📋 Tasks

- [x] **1.1** 문제 진단: 외부 curl timeout, 내부 curl 정상 확인
- [x] **1.2** SG `sg-0182701661cf2025c` (`dev-meta-k8s-common-sg`) 규칙 추가
  - TCP 80: `0.0.0.0/0` (sgr-078c766b58ccc2f21)
  - TCP 443: `0.0.0.0/0` (sgr-0bb678c1645abe5cd)
- [x] **1.3** 외부 접근 확인: HTTPS 200

## ⚠️ 참고

이 SG 변경은 AWS CLI로 직접 수행. Terraform에 SG 정의가 없으므로 (CCM 자동 생성),
Terraform 코드화는 후속 과제.

## 🔗 Dependencies

- `2026-02-07-nlb-target-automation.md` — NLB 타겟 관리 관련

## 🏷️ Labels

`security-group`, `nlb`, `ip-mode`, `networking`

## 📌 Priority / Status

**Critical** | ✅ **Done**
