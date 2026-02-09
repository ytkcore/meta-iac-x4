# Teleport App Service 구축 마무리

> **Status**: ✅ 완료  
> **Priority**: High  
> **Labels**: `teleport`, `app-access`, `access-gateway`, `security`  
> **작업 기간**: 2026-02-08 ~ 2026-02-09  
> **주요 커밋**: `93b8fa9`, `0c88e92`, `e98f00d`, `f0b0682`, `f18bada`, `7d36143`, `2df51cd`

---

## 📋 요약

Teleport App Service를 통해 **Internal NLB 뒤의 관리 도구(ArgoCD, Grafana 등)를
VPN 없이 Teleport 웹 콘솔에서 안전하게 접근**할 수 있도록 구축 완료.
80-access-gateway 스택의 Pluggable Architecture 설계, 서비스 등록,
와일드카드 인증서 생성, rewrite 설정까지 전 과정을 수행하고 디버깅하여 안정화.

---

## 🎯 목표

1. 80-access-gateway 스택 → Teleport App Service 동적 등록 파이프라인 구축
2. K8s Internal 서비스 8개 + EC2 자동 수집 서비스 Teleport 앱 등록
3. 와일드카드 자체서명 인증서로 App Access 서브도메인 TLS 해결
4. Keycloak rewrite_redirect 설정으로 내부 호스트명 리다이렉트 처리

---

## 📂 변경 파일

| 파일 | 변경 |
|:-----|:-----|
| `stacks/dev/80-access-gateway/main.tf` | Pluggable Architecture (Teleport 모듈 연동) |
| `stacks/dev/80-access-gateway/variables.tf` | `kubernetes_services` 서비스 목록 정의 |
| `modules/access-gateway/teleport/main.tf` | SSM 커맨드로 teleport.yaml app_service 병합 |
| `modules/teleport-ec2/user-data.sh` | 와일드카드 자체서명 인증서 생성 추가 |
| `modules/teleport-ec2/main.tf` | S3 IAM 권한 추가 (감사 로그 업로드) |

---

## ✅ 작업 내역

### Phase 1: 아키텍처 설계 (2/8)

- [x] **1.1** 80-access-gateway Pluggable Architecture 설계
  - `access_solution = "teleport"` 변수로 솔루션 독립적 구조
  - EC2 서비스: remote_state에서 자동 수집 (harbor, neo4j, opensearch)
  - K8s 서비스: `kubernetes_services` 변수로 수동 지정

### Phase 2: 서비스 등록 (2/9 새벽)

- [x] **2.1** 초기 서비스 등록 — argocd, grafana, longhorn, rancher (`93b8fa9`)
- [x] **2.2** 추가 등록 — vault, keycloak-admin (`0c88e92`)
- [x] **2.3** SSM 커맨드 수정 — teleport.yaml `app_service` 직접 병합 (`e98f00d`)

### Phase 3: 디버깅 (2/9)

- [x] **3.1** App Service 미등록 해결 — 별도 파일 → teleport.yaml 직접 병합 (`e98f00d`)
- [x] **3.2** 403 오류 해결 — `*.teleport.dev.unifiedmeta.net` 와일드카드 인증서 생성 (`f0b0682`)
- [x] **3.3** Keycloak 404 해결 — `rewrite_redirect` 설정 추가 (`f18bada`)
- [x] **3.4** YAML 이중 따옴표 제거 (`7d36143`)

### Phase 4: Observability 등록 (2/9 오후)

- [x] **4.1** alertmanager, prometheus 서비스 추가 등록 (`2df51cd`)

---

## 🔑 최종 등록 서비스 목록

| 서비스 | URI | 유형 | 비고 |
|:-------|:----|:-----|:-----|
| **argocd** | `https://argocd.unifiedmeta.net` | K8s Internal | — |
| **grafana** | `https://grafana.unifiedmeta.net` | K8s Internal | — |
| **longhorn** | `https://longhorn.unifiedmeta.net` | K8s Internal | — |
| **rancher** | `https://rancher.unifiedmeta.net` | K8s Internal | — |
| **vault** | `https://vault.dev.unifiedmeta.net` | K8s Internal | — |
| **keycloak-admin** | `https://keycloak.dev.unifiedmeta.net` | K8s Internal | `rewrite_redirect` 적용 |
| **alertmanager** | `https://alertmanager.unifiedmeta.net` | K8s Internal | — |
| **prometheus** | `https://prometheus.unifiedmeta.net` | K8s Internal | — |
| **harbor** | `https://harbor.unifiedmeta.net` | EC2 자동 | user-data.sh 기본 포함 |

---

## 🔧 핵심 해결 사항

### 1. App Access 403 — 와일드카드 인증서

Teleport App Access는 `<app>.teleport.dev.unifiedmeta.net` 서브도메인을 사용.
`proxy.crt`에 `*.teleport.dev.unifiedmeta.net` SAN이 없으면 `/x-teleport-auth` POST에서 403 반환.

```bash
# user-data.sh에 추가
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /var/lib/teleport/proxy.key \
  -out /var/lib/teleport/proxy.crt \
  -subj "/CN=$CLUSTER_NAME" \
  -addext "subjectAltName=DNS:$CLUSTER_NAME,DNS:*.$CLUSTER_NAME,..."
```

### 2. SSM 커맨드 — teleport.yaml 직접 병합

기존: `apps.yaml` 별도 파일 → Teleport가 미로딩  
수정: Python YAML로 `teleport.yaml`의 `app_service` 섹션 직접 병합 후 재시작

### 3. Keycloak rewrite_redirect

Keycloak Admin 접근 시 내부 호스트명(`keycloak.dev.unifiedmeta.net`)으로 리다이렉트 → Teleport 프록시 도메인과 불일치.
`rewrite_redirect` 설정으로 내부 호스트명 → Teleport 앱 도메인 자동 변환.

---

## 🔗 관련 티켓

- [access-gateway-stack](2026-02-07-access-gateway-stack.md) — 80-access-gateway 스택 설계 원본
- [teleport-keycloak-rewrite-fix](2026-02-09-teleport-keycloak-rewrite-fix.md) — rewrite_redirect 디버깅 상세
- [infra-codification-sg-teleport](2026-02-09-infra-codification-sg-teleport.md) — Observability 앱 등록 포함
- [teleport-ha-access-control](2026-02-04-teleport-ha-access-control.md) — Teleport HA 기반 인프라
- [loki-gateway-dns-fix](2026-02-09-loki-gateway-dns-fix.md) — Observability 등록과 동시 커밋

---

## 📝 비고

- EC2 서비스(harbor, neo4j, opensearch)는 각 스택의 `service_endpoint` output을 자동 수집
- `access_solution` 변수를 `"none"`으로 변경하면 Teleport 없이도 스택 동작 가능 (Pluggable)
- 향후 Boundary 등 대체 솔루션 추가 시 `modules/access-gateway/boundary/` 모듈만 추가하면 됨
