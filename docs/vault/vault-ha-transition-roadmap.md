# Vault HA 전환 로드맵

> **목적**: 현재 Dev-grade Vault 배포의 보안 리스크를 식별하고, Production-grade HA 구성으로 전환하기 위한 단계별 로드맵을 정의한다.

## 1. 현재 구성 분석 (As-Is)

| 항목 | 현재 값 | 위험도 | 비고 |
|------|---------|--------|------|
| **Mode** | Standalone | 🔴 HIGH | SPOF — Pod 재시작 시 서비스 중단 |
| **Storage** | `file` (local PVC) | 🔴 HIGH | Raft 미사용, 복제 없음 |
| **HA Enabled** | `false` | 🔴 HIGH | Failover 없음 |
| **Seal Type** | Shamir (5/3) | 🟡 MED | 수동 unseal 필요 — 재시작마다 3개 키 입력 |
| **TLS Listener** | `tls_disable = 1` | 🟡 MED | Pod↔Ingress 간 plaintext (Ingress TLS 종단) |
| **Replicas** | 1 | 🔴 HIGH | 단일 Pod 장애 → 전체 Vault 중단 |
| **Storage Size** | 10Gi (Longhorn) | 🟢 LOW | Dev 환경에 적절 |
| **Injector** | Enabled | 🟢 OK | ALBC 등 workload identity 정상 작동 |
| **CSI Provider** | Disabled | 🟢 OK | Phase 확장 시 활성화 |
| **Version** | 1.17.2 | 🟢 OK | 최신 안정 릴리스 |

### 현재 의존 서비스
- **ALBC**: Vault AWS Secrets Engine → STS 임시 자격증명 (`/vault/secrets/aws-creds`)
- **Grafana**: Keycloak OIDC (Vault 직접 의존은 없으나 향후 확장 대상)

## 2. 위험 시나리오

| 시나리오 | 영향 | 현재 대응 |
|----------|------|-----------|
| vault-0 Pod 재시작 | Sealed 상태 → 수동 unseal 필요, ALBC credential 갱신 중단 | 없음 (수동 개입) |
| 워커 노드 장애 | Vault 완전 중단, PVC 재마운트 대기 | Longhorn 복제로 데이터 보존 |
| Longhorn Volume 손상 | 데이터 유실 (백업 미구성 시) | Longhorn S3 backup (구성 여부 확인 필요) |
| 네트워크 파티션 | Standalone이므로 영향 없음 | N/A |

## 3. HA 전환 로드맵 (To-Be)

### Phase A: Auto-Unseal (우선순위 1) — 즉시 적용 가능

> Pod 재시작 시 자동 unseal로 운영 부담 제거

```hcl
# vault.yaml → standalone.config 추가
seal "awskms" {
  region     = "ap-northeast-2"
  kms_key_id = "<KMS_KEY_ID>"
}
```

**필요 작업:**
1. AWS KMS 키 생성 (Terraform `55-bootstrap` 또는 별도 stack)
2. Vault Pod에 KMS 권한 부여 (Node Role 또는 IRSA)
3. `seal "shamir"` → `seal "awskms"` 마이그레이션 (`vault operator seal -migrate`)
4. 기존 Shamir 키는 Recovery Keys로 보관

**예상 다운타임**: 5~10분 (seal migration 중)

---

### Phase B: Raft HA (우선순위 2) — 안정화 후

> 3-replica Active/Standby 구성으로 SPOF 제거

```yaml
# vault.yaml 변경
server:
  ha:
    enabled: true
    replicas: 3
    raft:
      enabled: true
      config: |
        ui = true
        listener "tcp" {
          tls_disable = 1
          address     = "[::]:8200"
          cluster_address = "[::]:8201"
        }
        storage "raft" {
          path = "/vault/data"
          retry_join {
            leader_api_addr = "http://vault-0.vault-internal:8200"
          }
          retry_join {
            leader_api_addr = "http://vault-1.vault-internal:8200"
          }
          retry_join {
            leader_api_addr = "http://vault-2.vault-internal:8200"
          }
        }
        seal "awskms" {
          region     = "ap-northeast-2"
          kms_key_id = "<KMS_KEY_ID>"
        }
  standalone:
    enabled: false
```

**필요 작업:**
1. Phase A (Auto-Unseal) 선행 완료
2. `file` → `raft` storage migration (snapshot + restore)
3. PodAntiAffinity 설정 (노드 분산)
4. PDB `minAvailable: 2` 설정
5. `vault-internal` headless service 확인 (이미 존재)

**예상 다운타임**: 15~30분 (storage migration)

---

### Phase C: TLS 종단간 암호화 (우선순위 3) — 선택적

> Pod 내부 listener에서 TLS 활성화

```hcl
listener "tcp" {
  tls_disable    = 0
  address        = "[::]:8200"
  tls_cert_file  = "/vault/tls/tls.crt"
  tls_key_file   = "/vault/tls/tls.key"
}
```

**필요 작업:**
1. cert-manager Certificate CR 생성 (vault.vault.svc)
2. Volume mount 추가
3. Ingress backend-protocol 변경 (`HTTPS`)
4. Injector의 vault 주소 변경 (`https://`)

**영향도**: 설정 복잡도 증가, dev 환경에서는 불필요

## 4. 권장 실행 순서

```
현재 (Dev)               Phase A              Phase B              Phase C
┌─────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Standalone   │ ──▶ │ + Auto-Unseal│ ──▶ │ Raft HA (3)  │ ──▶ │ + TLS E2E    │
│ Shamir 5/3   │     │   (AWS KMS)  │     │ + Anti-Aff   │     │   (Optional) │
│ File Storage │     │              │     │ + PDB        │     │              │
│ 1 Replica    │     │ 1 Replica    │     │ 3 Replicas   │     │ 3 Replicas   │
└─────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
   Dev 환경 OK          Staging 필수          Production 필수       Enterprise급
```

## 5. Dev 환경 결론

| 판단 | 근거 |
|------|------|
| **현재 구성 유지** (당분간) | Dev 환경, ALBC만 의존, 재시작 빈도 낮음 |
| **Phase A 우선 검토** | KMS auto-unseal은 비용 낮고 운영 부담 크게 감소 |
| **Phase B는 Staging/Prod 시** | Raft HA는 리소스 3배, 복잡도 증가 |
| **Phase C는 Enterprise 시** | 내부 TLS는 compliance 요구 시에만 |

---

*작성일: 2026-02-08 | 기준 환경: dev (RKE2 + Cilium)*
*Vault Version: 1.17.2 | Helm Chart: 0.28.1*
