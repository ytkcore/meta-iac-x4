# [INFRA] Teleport HA 배포 + Access Control 체계 구축

## 📋 Summary

AWS Client VPN을 **Teleport**로 대체하여 Zero-Trust 기반 접근 제어 체계를 구축한다.
Teleport EC2 HA(2AZ) + WAF + App Access를 통해 SSH, 웹서비스, DB 접근을 통합 관리한다.

## 🎯 Goals

1. **VPN → Teleport 전환**: Client VPN 제거, Teleport 기반 접근
2. **HA 배포**: 2 AZ(a, c)에 Teleport EC2 배치
3. **WAF 보호**: Teleport ALB 앞단에 AWS WAF 배치
4. **App Access**: 내부 서비스(Harbor, ArgoCD, Grafana 등) 통합 접근
5. **세션 녹화**: 모든 SSH/웹 접근 감사 로그

## 📊 아키텍처

```
외부 사용자
  → Teleport Proxy (Public ALB + WAF)
    → Teleport Auth
      → SSH: EC2 인스턴스 직접 접근
      → Web: Internal 서비스 프록시
      → DB:  PostgreSQL/Neo4j 접근 (추후)
      → K8s: kubectl 통합 (추후)
```

## 📋 Tasks (완료)

### Teleport 배포
- [x] `modules/teleport-ec2/` 모듈 생성 (main.tf, variables.tf, outputs.tf, user-data.sh)
- [x] `stacks/dev/15-teleport/` 스택 생성
- [x] Teleport EC2 HA (2 인스턴스, AZ-a + AZ-c)
- [x] Internal ALB + ACM 인증서
- [x] DynamoDB 백엔드 (클러스터 상태 저장)
- [x] Route53 DNS: `teleport.unifiedmeta.net`

### WAF 구축
- [x] `modules/waf-acl/` 재사용 가능 모듈 생성
- [x] `stacks/dev/20-waf/` 스택 생성
- [x] WAF ACL → Teleport ALB 연결
- [x] Rate Limiting + IP 차단 규칙

### Access Control 문서화
- [x] Teleport 배포 가이드 (`docs/access-control/teleport-ec2-deployment-guide.md`)
- [x] Teleport 운영 매뉴얼 (`docs/access-control/teleport-operations-manual.md`)
- [x] Teleport 사용자 가이드 (`docs/access-control/teleport-user-guide.md`)
- [x] ADR-001: 접근 제어 솔루션 선정 (`docs/access-control/ADR-001-access-control-solution.md`)
- [x] 보안 정책 문서 (`docs/security/comprehensive-security-policy.md`)
- [x] SSH 운영 정책 (`docs/security/ssh-operational-policy.md`)

### VPN 정리
- [x] AWS Client VPN 리소스 수동 삭제 스크립트 작성
- [x] VPN Authorization Rule, Network Association, Endpoint 삭제
- [x] VPN 관련 SG, ACM 인증서 삭제
- [x] `15-vpn` 스택 코드 완전 제거

## 🔧 주요 변경 파일

| 범주 | 파일 |
|------|------|
| Teleport 모듈 | `modules/teleport-ec2/` (4파일) |
| Teleport 스택 | `stacks/dev/15-teleport/` (5파일) |
| WAF 모듈 | `modules/waf-acl/` (3파일) |
| WAF 스택 | `stacks/dev/20-waf/` (5파일) |
| VPN 정리 | `scripts/cleanup/remove-vpn-stack.sh` |
| 문서 | `docs/access-control/` (7파일), `docs/security/` (2파일) |

## 📊 검증 결과

| 항목 | 상태 |
|------|------|
| Teleport Web UI 접근 | ✅ |
| SSM 기반 초기 관리자 생성 | ✅ |
| SSH 세션 녹화 | ✅ |
| WAF 규칙 동작 | ✅ |
| VPN 리소스 전수 삭제 | ✅ |

## 📎 References

- [13-access-gateway-architecture.md](../architecture/13-access-gateway-architecture.md)
- [15-teleport-replacement-strategy.md](../architecture/15-teleport-replacement-strategy.md)
- [VPN 수동 정리 가이드](../troubleshooting/client-vpn-manual-cleanup.md)
- [Teleport 공식 문서](https://goteleport.com/docs/)

## 🏷️ Labels

`teleport`, `access-control`, `vpn-removal`, `waf`, `zero-trust`

## 📌 Priority / Status

**Critical** / ✅ 완료 (2026-02-04~06)
