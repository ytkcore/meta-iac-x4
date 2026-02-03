# 70. Observability Stack Specification (v3.0 - Final Master)

## 0. 프롬프트
# Role Definition
당신은 'Anti-Gravity' 팀의 리드 DevOps 엔지니어입니다.
당신의 임무는 플랫폼의 기반이 되는 `Monitoring`과 `Longhorn` 스택을 **"Enterprise Grade (Security + HA + Performance)"** 수준으로 최종 구축하는 것입니다.

# Input Assets
1. **Target Files:**
   - `meta.v1/gitops-apps/platform/monitoring.yaml`
   - `meta.v1/gitops-apps/platform/longhorn.yaml`
2. **Specification:** `docs/Specification/70-observability.md`
3. **Optimized Code Reference:** (위에서 제공된 YAML 코드 2종)

# Task Specification (Action Items)
제공된 [Optimized Code Reference]의 내용을 각 파일에 반영하되, 다음 핵심 검증 포인트(Audit Points)를 반드시 통과해야 합니다.

## 1. Environment Adaptation (Domain Config)
* **Sibling Domain Rule:** 코드 내의 도메인은 현재 배포 환경의 **`unifiedmeta.net`**으로 정확히 치환되었습니다.
    - `grafana.unifiedmeta.net`
    - `longhorn.unifiedmeta.net`
    - `prometheus.unifiedmeta.net`
* **Deep Links:** ArgoCD Application의 `annotations`에 있는 링크들도 동일한 도메인으로 치환되었음을 확인하였습니다.

## 2. High Availability & Performance Validation
* **Longhorn:** `defaultClassReplicaCount: 3` 확인.
* **Alertmanager:** `replicas: 3` 확인.
* **Prometheus:** `walCompression: true` (Longhorn 최적화 필수) 및 `memory request: 1Gi` 확인.

## 3. Security Check
* `grafana.adminPassword`가 삭제되고 `existingSecret`을 사용하는지 확인.
* Ingress에 `ssl-redirect: "true"` 및 `X-Frame-Options` 헤더가 설정되었는지 확인.

# Output Action
* 위 검증을 마친 최종 `monitoring.yaml`과 `longhorn.yaml` 파일의 전체 내용을 출력하십시오.
* (중요) 사용자가 사전에 `monitoring-grafana-secret`을 생성해야 함을 상기시키는 안내 메시지를 함께 출력하십시오.

## 1. 개요
본 문서는 RKE2 클러스터의 관측성(Observability) 및 스토리지(Storage) 표준을 정의합니다.
CSP(AWS/Azure)에 종속되지 않는 **Cloud Agnostic** 아키텍처를 지향하며, 금융권 수준의 **보안(Security)**과 **고가용성(HA)**을 보장합니다.

## 2. 아키텍처 원칙 (Architecture Principles)
* **Storage Independence:** 데이터 레이어는 `Longhorn`으로 추상화하여, 클라우드 이전(Migration) 시 데이터 종속성을 제거합니다.
* **Resilience First:** 모든 핵심 컴포넌트(Alertmanager, Longhorn)는 **3-Replicas(Quorum)** 구성을 원칙으로 하여, 단일 노드 장애 시에도 서비스를 유지합니다.
* **Operational Visibility:** ArgoCD와 Grafana/Longhorn UI는 유기적으로 연결(Deep Links)되어야 하며, 운영자에게 최적의 UX를 제공합니다.

## 3. 상세 기술 사양 (Technical Specifications)

### 3.1 Prometheus (Core Engine)
* **Performance:** Longhorn 스토리지 I/O 부하를 50% 이상 절감하기 위해 **WAL Compression**을 필수 적용합니다.
* **QoS:** OOM 방지를 위해 `Request Memory`를 `1Gi`로 상향하여 안정성을 확보합니다.
* **Retention:** `15d` / `20Gi` (로컬 단기 보관).

### 3.2 Alertmanager (Notification HA)
* **Clustering:** 3개의 레플리카로 구성하며, `PodAntiAffinity`를 강제하여 물리적 장애 도메인을 분리합니다.

### 3.3 Grafana & UI (Security & UX)
* **Identity:** Admin 패스워드는 K8s Secret(`monitoring-grafana-secret`)으로만 관리합니다.
* **Hardening:** `grafana.ini`를 통해 익명 접속을 차단하고, `X-Frame-Options: DENY` 헤더를 적용합니다.
* **Domain Rule (Sibling Strategy):** 모든 UI 도메인은 ArgoCD의 하위가 아닌, **Base Domain의 직계 형제**로 구성합니다. (예: `grafana.{base_domain}`)

### 3.4 Longhorn (Storage Foundation)
* **Replication:** 운영 환경 표준인 **Replica Count: 3**을 적용하여 데이터 정합성을 보장합니다.
* **Network:** Ingress를 통해 UI를 노출하되, Basic Auth 등의 추가 인증 수단을 권장합니다.

## 4. 운영 전략
* **ArgoCD Integration:** ArgoCD 대시보드에서 각 시스템으로 바로 이동할 수 있는 `External Link`를 제공합니다.
* **Deploy Policy:** 대용량 CRD 처리를 위한 `ServerSideApply` 및 강력한 `Retry(10회)` 정책을 적용합니다.