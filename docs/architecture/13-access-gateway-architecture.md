# Access Gateway Architecture — 솔루션 독립적 접근 제어 계층

**작성일**: 2026-02-07  
**상태**: 설계 완료 / 구현 대기  
**관련 스택**: `80-access-gateway`, `15-access-control`

---

## 1. 개요

모든 내부 서비스(Harbor, ArgoCD, Grafana, Neo4j, OpenSearch 등)에 대한 **통합 접근 제어 계층**을 정의합니다.
핵심 설계 원칙은 **"서비스 스택이 특정 접근 제어 솔루션에 의존하지 않는"** 솔루션 독립적(Solution-Agnostic) 아키텍처입니다.

### 설계 목표

| 목표 | 설명 |
|------|------|
| **솔루션 독립성** | 서비스 스택에 Teleport/Boundary 등 특정 솔루션 의존성 없음 |
| **자동 수집** | `service_endpoint` output 패턴으로 서비스 자동 수집 |
| **확장성** | 접근 제어 솔루션 변경 시 모듈만 교체 (서비스 스택 무변경) |
| **일관성** | 모든 내부 서비스에 대한 통합 접근 경로 제공 |

---

## 2. 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│  서비스 스택들                                                    │
│  40-harbor, 55-bootstrap, 61-neo4j, 62-opensearch, ...          │
│                                                                 │
│  output "service_endpoint" = {                                  │
│    name     = "harbor"                                          │
│    uri      = "https://harbor.unifiedmeta.net"                  │
│    type     = "web"                                             │
│    internal = true                                              │
│  }                                                              │
└─────────────────────────────────────────────────────────────────┘
                              ↓ Remote State 참조
┌─────────────────────────────────────────────────────────────────┐
│  80-access-gateway                                              │
│                                                                 │
│  1. 모든 스택에서 service_endpoint 수집                          │
│  2. null 제외, internal = true 필터링                            │
│  3. access_solution 변수에 따라 솔루션 모듈 적용                  │
│     - teleport: modules/access-gateway/teleport (현재)          │
│     - boundary: modules/access-gateway/boundary (미래)          │
│     - guacamole: modules/access-gateway/guacamole (미래)        │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  접근 제어 솔루션 (현재: Teleport App Access)                     │
│                                                                 │
│  harbor.teleport.unifiedmeta.net   → harbor.unifiedmeta.net     │
│  argocd.teleport.unifiedmeta.net   → argocd.unifiedmeta.net     │
│  grafana.teleport.unifiedmeta.net  → grafana.unifiedmeta.net    │
│  neo4j.teleport.unifiedmeta.net    → neo4j.unifiedmeta.net      │
│  opensearch.teleport.unifiedmeta.net → opensearch.unifiedmeta.net│
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. service_endpoint 표준 인터페이스

서비스 스택은 접근 제어 솔루션에 대해 알 필요 없이, **표준 인터페이스**만 제공합니다.

```hcl
# 스키마 정의
output "service_endpoint" {
  value = {
    name     = string   # 서비스 이름 (e.g., "harbor")
    uri      = string   # 내부 접근 URI
    type     = string   # web | api | db
    internal = bool     # Private 접근 필요 여부
  }
}
```

### 등록 대상 서비스

| 서비스 | 배포 스택 | 유형 | URI |
|:---|:---|:---|:---|
| Harbor | `40-harbor` | EC2 (web) | `https://harbor.unifiedmeta.net` |
| ArgoCD | `55-bootstrap` | K8s (web) | `https://argocd.unifiedmeta.net` |
| Grafana | `70-observability` | K8s (web) | `https://grafana.unifiedmeta.net` |
| Longhorn | `55-bootstrap` | K8s (web) | `https://longhorn.unifiedmeta.net` |
| Neo4j | `61-neo4j` | EC2 (web) | `https://neo4j.unifiedmeta.net:7473` |
| OpenSearch | `62-opensearch` | EC2 (web) | `https://opensearch.unifiedmeta.net` |

---

## 4. 솔루션 선택 전략

```hcl
variable "access_solution" {
  description = "접근 제어 솔루션 선택"
  type        = string
  default     = "teleport"  # teleport | boundary | guacamole | none
}
```

### 솔루션별 비교

| 항목 | Teleport | Boundary | Apache Guacamole |
|------|----------|----------|------------------|
| 라이선스 | AGPLv3 (사내 전용) | BSL | **Apache 2.0** (납품 가능) |
| 프로토콜 | SSH, K8s, DB, Web | SSH, DB, K8s | RDP, SSH, VNC |
| Windows RDP | Enterprise 전용 | 미지원 | **네이티브 지원** |
| 세션 녹화 | ✅ | ❌ | ✅ |
| K8s 접근 | ✅ 네이티브 | ✅ | ⚠️ SSH 경유 |

> **전략**: 사내 환경은 **Teleport**, B2B/납품 환경은 **Apache Guacamole** 사용.
> 80-access-gateway 스택의 모듈 교체만으로 솔루션 전환 가능.

---

## 5. 설계 원칙

1. **서비스 스택 ↔ 접근 제어 느슨한 결합**: 서비스 스택은 `output`만 제공, 솔루션 모듈이 수집
2. **확장 시 모듈만 추가**: 새 솔루션은 `modules/access-gateway/<solution>/`에 모듈 추가
3. **신규 서비스 추가 시 output만 추가**: 서비스 스택에 `service_endpoint` output만 정의하면 자동 등록
4. **Remote State 기반 자동 수집**: `try()` 함수로 안전하게 처리, 미배포 스택은 null 반환
