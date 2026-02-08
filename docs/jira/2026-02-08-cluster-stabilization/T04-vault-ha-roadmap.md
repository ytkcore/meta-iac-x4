# T4: Vault HA 전환 로드맵 문서화

> **Parent**: [클러스터 안정화](../2026-02-08-cluster-stabilization.md) | **Status**: ✅ 완료

## 📋 Summary

현재 Dev-grade Vault(Standalone, file storage)의 보안 리스크를 분석하고, Production-grade HA 전환을 위한 3-Phase 로드맵을 문서화.

## 🔍 현재 구성 (As-Is)

| 항목 | 현재 값 | 위험도 |
|------|---------|--------|
| Mode | Standalone | 🔴 HIGH (SPOF) |
| Storage | `file` (local PVC) | 🔴 HIGH (복제 없음) |
| HA | `false` | 🔴 HIGH (Failover 없음) |
| Seal | ~~Shamir 5/3~~ → **KMS** | ✅ DONE |
| TLS Listener | `tls_disable = 1` | 🟡 MED |
| Replicas | 1 | 🔴 HIGH |

## 🗺️ 3-Phase 로드맵

### Phase A: Auto-Unseal ✅ (완료)
> Pod 재시작 시 자동 unseal → 운영 부담 제거

- AWS KMS 키 생성 (`fcaa0e8d`, key rotation 활성)
- `seal "awskms"` stanza 추가
- Shamir → KMS seal migration
- IMDS hop_limit=2 (Cilium ENI 필수)

**다운타임**: 5분 (migration 중)

### Phase B: Raft HA (다음 단계)
> Standalone → 3-replica Raft 클러스터로 SPOF 제거

```yaml
# 계획
server:
  ha:
    enabled: true
    replicas: 3
    raft:
      enabled: true
```

**다운타임**: 15-30분 (데이터 마이그레이션)

### Phase C: TLS E2E (최종)
> Pod 간 + Listener 전구간 TLS 암호화

```yaml
server:
  extraEnvironmentVars:
    VAULT_ADDR: "https://localhost:8200"
    VAULT_CACERT: "/vault/tls/ca.crt"
```

**다운타임**: 5분 (인증서 교체)

## 📄 생성된 문서

| 문서 | 경로 | 내용 |
|------|------|------|
| HA 로드맵 | `docs/vault/vault-ha-transition-roadmap.md` | 3-Phase 로드맵 전체 |
| KMS Auto-Unseal | `docs/vault/vault-kms-auto-unseal.md` | Phase A 상세 운영 가이드 |

## 🔧 변경 파일

| 파일 | 변경 | 커밋 |
|------|------|------|
| `docs/vault/vault-ha-transition-roadmap.md` | [NEW] 로드맵 문서 | `a639e8f` |

## 🏷️ Labels
`vault`, `ha`, `documentation`, `roadmap`
