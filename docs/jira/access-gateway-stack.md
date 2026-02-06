# [INFRA] 80-access-gateway 스택 구현 - 솔루션 독립적 접근 제어 계층

## 📋 Summary

모든 내부 서비스(Harbor, ArgoCD, Grafana, Neo4j, OpenSearch 등)에 대한 통합 접근 제어 계층을 구현합니다. 
각 서비스 스택은 표준화된 `service_endpoint` output을 제공하고, 80-access-gateway 스택이 이를 수집하여 
선택된 접근 제어 솔루션(Teleport, Boundary 등)에 등록합니다.

## 🎯 Goals

1. **솔루션 독립성**: 서비스 스택이 특정 접근 제어 솔루션에 의존하지 않음
2. **자동 수집**: 서비스 엔드포인트를 자동으로 수집하여 등록
3. **확장성**: 새로운 접근 제어 솔루션 추가 시 모듈만 추가
4. **일관성**: 모든 내부 서비스에 대한 통합 접근 경로 제공

## 📊 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  서비스 스택들                                                    │
│  40-harbor, 61-neo4j, 62-opensearch, ...                        │
│                                                                 │
│  output "service_endpoint" = {                                  │
│    name     = "harbor"                                          │
│    uri      = "https://harbor.unifiedmeta.net"                  │
│    type     = "web"                                             │
│    internal = true                                              │
│  }                                                              │
│  # 서비스 없는 스택: null                                         │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  80-access-gateway                                              │
│                                                                 │
│  1. 모든 스택에서 service_endpoint 수집                          │
│  2. null 제외, internal = true 필터링                            │
│  3. access_solution 변수에 따라 솔루션 적용                       │
│     - teleport: modules/access-gateway/teleport                 │
│     - boundary: modules/access-gateway/boundary (미래)          │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  Teleport App Access (현재 기본)                                 │
│                                                                 │
│  harbor.teleport.unifiedmeta.net → harbor.unifiedmeta.net       │
│  argocd.teleport.unifiedmeta.net → argocd.unifiedmeta.net       │
│  grafana.teleport.unifiedmeta.net → grafana.unifiedmeta.net     │
│  ...                                                            │
└─────────────────────────────────────────────────────────────────┘
```

## 📋 Tasks

### Phase 1: 표준 Output 정의

- [ ] **1.1** `service_endpoint` output 스키마 정의
  ```hcl
  type = object({
    name     = string           # 서비스 이름
    uri      = string           # 내부 접속 URI
    type     = string           # web, api, db
    internal = bool             # Private 접근 필요 여부
  })
  ```

- [ ] **1.2** 각 서비스 스택에 output 추가
  - `40-harbor/outputs.tf`
  - `55-bootstrap/outputs.tf` (ArgoCD, Longhorn)
  - `61-neo4j/outputs.tf`
  - `62-opensearch/outputs.tf`
  - `70-observability/outputs.tf` (Grafana)

- [ ] **1.3** 인프라 스택에 null output 추가 (선택적)
  - `00-network`, `05-security`, `10-golden-image` 등

### Phase 2: access-gateway 모듈 생성

- [ ] **2.1** `modules/access-gateway/teleport/` 모듈 생성
  - 서비스 목록을 받아 Teleport App 설정 생성
  - SSM으로 Teleport 서버에 설정 적용

- [ ] **2.2** `modules/access-gateway/common/` 공통 모듈 (선택적)
  - 서비스 필터링, 변환 로직

### Phase 3: 80-access-gateway 스택 생성

- [ ] **3.1** 스택 기본 구조 생성
  ```
  stacks/dev/80-access-gateway/
  ├── main.tf
  ├── variables.tf
  ├── outputs.tf
  └── versions.tf
  ```

- [ ] **3.2** Remote State 수집 로직 구현
  - 모든 서비스 스택에서 `service_endpoint` 수집
  - `try()` 함수로 안전하게 처리

- [ ] **3.3** 솔루션 선택 로직 구현
  ```hcl
  variable "access_solution" {
    default = "teleport"  # teleport, boundary, none
  }
  ```

- [ ] **3.4** `config.mk` STACK_ORDER 업데이트
  ```makefile
  STACK_ORDER := ... 70-observability 80-access-gateway
  ```

### Phase 4: K8s 서비스 지원

- [ ] **4.1** K8s 서비스 목록 변수 추가
  ```hcl
  variable "kubernetes_services" {
    default = [
      { name = "argocd",   uri = "https://argocd.unifiedmeta.net", ... },
      { name = "grafana",  uri = "https://grafana.unifiedmeta.net", ... },
      { name = "longhorn", uri = "https://longhorn.unifiedmeta.net", ... },
    ]
  }
  ```

- [ ] **4.2** EC2 + K8s 서비스 통합 로직

### Phase 5: 검증

- [ ] **5.1** `make apply-all` 전체 배포 테스트
- [ ] **5.2** Teleport 앱 접근 테스트
- [ ] **5.3** 신규 서비스 추가 시나리오 테스트

## 🔗 Dependencies

- `15-access-control`: Teleport 서버 Instance ID
- 각 서비스 스택: `service_endpoint` output

## 📊 등록 대상 서비스

| 서비스 | 배포 스택 | 유형 | URI |
|:---|:---|:---|:---|
| Harbor | 40-harbor | EC2 | `https://harbor.unifiedmeta.net` |
| ArgoCD | 55-bootstrap | K8s | `https://argocd.unifiedmeta.net` |
| Grafana | 70-observability | K8s | `https://grafana.unifiedmeta.net` |
| Longhorn | 55-bootstrap | K8s | `https://longhorn.unifiedmeta.net` |
| Neo4j | 61-neo4j | EC2 | `https://neo4j.unifiedmeta.net:7473` |
| OpenSearch | 62-opensearch | EC2 | `https://opensearch.unifiedmeta.net` |

## 📋 Acceptance Criteria

- [ ] 서비스 스택에 Teleport 의존성 없음
- [ ] `make apply-all` 시 자동으로 앱 등록
- [ ] 신규 서비스 추가 시 해당 스택에 output만 추가하면 됨
- [ ] `access_solution` 변수로 솔루션 변경 가능

## 📎 References

- [Teleport App Access Workflow 다이어그램](../diagrams/teleport-rke2-app-access-workflow.png)
- [Teleport Application Access 공식 문서](https://goteleport.com/docs/application-access/)

## 📝 Notes

- 초기 구현은 Teleport만 지원
- Boundary 등 다른 솔루션은 미래 확장으로 모듈만 추가
- K8s 서비스는 GitOps로 배포되므로 변수로 관리 (자동 수집 어려움)
