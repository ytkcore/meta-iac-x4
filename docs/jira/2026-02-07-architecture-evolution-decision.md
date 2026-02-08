# [INFRA] 플랫폼 아키텍처 고도화 — 최종 의사결정

## 📋 Summary

플랫폼 Identity/Secrets/Access 아키텍처를 **3-Layer Stack**으로 고도화하는 최종 의사결정을 문서화합니다.
4-Layer(SPIRE 포함) 원안에서 현재 규모에 맞게 SPIRE를 보류하고, Keycloak이 L1+L2(SSO+Workload OIDC)를 겸하는 실용적 구조로 확정했습니다.

## 🎯 Decision

```
3-Layer Identity Stack:
  L3  Teleport   ── 접근 프록시 + 감사        ✅ 유지
  L2  Vault      ── 동적 시크릿 + 자동 회전    🆕 신규
  L1  Keycloak   ── SSO + Workload OIDC       🆕 신규
```

## 📊 배경

| 의사결정 문서 | 핵심 질문 | 결론 |
|-------------|----------|------|
| 12-platform-identity-architecture | 4-Layer Stack 원안 | SPIRE는 현재 규모에서 과잉 |
| 13-access-gateway-architecture | 솔루션 독립 접근 제어 | Teleport 유지, 모듈화 완료 |
| 14-future-roadmap | 어떤 순서로 고도화? | ALBC → Keycloak → Vault → CCM 제거 |
| market-player-infrastructure-research | 업계는 뭘 쓰나? | Atlan=Keycloak+Vault, 3사 전원 동일 |
| platform-identity-bridge-strategy | SPIRE 없이 가능? | Keycloak OIDC가 Bridge 역할 대체 |

## 📎 관련 문서

- [16-architecture-evolution-decision.md](../../docs/architecture/16-architecture-evolution-decision.md)

## 🏷️ Labels

`architecture`, `identity`, `decision`

## 📌 Priority

**Critical**
