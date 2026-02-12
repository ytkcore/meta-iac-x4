# AIPP (AI Hub) 자체 솔루션 클러스터 배포 전략

**작성일**: 2026-02-11  
**환경**: dev-meta RKE2 클러스터  
**관련 문서**: [웹서비스 온보딩](./web-service-onboarding.md), [서비스 아키텍처 가이드](./new-service-architecture-tips.md)

---

## 1. 개요

외부 벤더의 Docker Compose 기반 AI Hub 솔루션 패키지(AIPP)를 K8s 클러스터에 네이티브 배포하기 위한 전략 문서.

### 왜 K8s 전환인가?

| 관점 | Docker Compose (원본) | K8s 배포 (전환) |
|------|---------------------|----------------|
| **고가용성** | 단일 호스트 | Pod 재시작, Node 장애 복원 |
| **시크릿 관리** | `.env` 파일 | Vault Agent Sidecar |
| **스토리지** | 로컬 bind mount | Longhorn PVC (분산 스토리지) |
| **모니터링** | 별도 Observability 스택 필요 | 기존 Prometheus/Loki/Tempo 연동 |
| **배포 파이프라인** | 수동 `docker-compose up` | ArgoCD GitOps 자동화 |
| **네트워크/보안** | 포트 직접 노출 | Ingress + TLS + NetworkPolicy |

### 소스 패키지 위치

- 원본: [gitops-apps/apps/aipp/package](file:///Users/ytkcloud/cloud/meta/gitops-apps/apps/aipp/package)
- K8s 매니페스트 (생성 예정): `gitops-apps/apps/aipp/k8s/`

---

## 2. 서비스 구성 분석

### 2.1 서비스 인벤토리 (8 서비스)

| 서비스 | 유형 | 이미지 | K8s 리소스 | 비고 |
|--------|------|--------|-----------|------|
| pgvector | Infra/DB | `pgvector/pgvector:pg17` | StatefulSet + PVC | pgvector 확장, init 스크립트 |
| redis | Infra/Cache | `redis:7` | Deployment + PVC | 패스워드 인증 |
| rabbitmq | Infra/MQ | `rabbitmq:3-management` | StatefulSet + PVC | Management UI 포함 |
| enai-front | App/FE | `registry.gitlab.../front-next:latest` | Deployment (2r) | React + PM2 |
| enai-backend | App/BE | `registry.gitlab.../backend:latest` | Deployment (1r) | Spring Boot + Liquibase |
| enai-data-processor | App/Worker | `registry.gitlab.../catalog-collector:latest` | Deployment (1r) | Spring Boot |
| enai-linker | App/AI | `registry.gitlab.../linker:main-latest` | Deployment (1r) | **GPU 필수** ⚠️ |
| enai-scheduler | App/Cron | `registry.gitlab.../scheduler:latest` | Deployment (1r) | Spring Boot |

### 2.2 서비스 의존성 순서

```
[Wave 0] Namespace + Secrets + ConfigMaps
    ↓
[Wave 1] pgvector, redis, rabbitmq
    ↓
[Wave 2] enai-backend (DB/Cache/MQ 의존)
    ↓
[Wave 3] enai-data-processor, enai-linker, enai-scheduler (backend 의존)
    ↓
[Wave 4] enai-front + Ingress
```

---

## 3. 이미지 Pull 전략 ⚠️

### 3.1 현황

- **공식 이미지** (`pgvector`, `redis`, `rabbitmq`): Harbor `dockerhub-proxy`로 정상 Pull 가능
- **AIPP 커스텀 이미지**: `registry.gitlab.enai-rnd-2.en-core.info:10003` — **현재 접근 불가**

### 3.2 이슈 분석

| 이슈 | 상세 | 심각도 |
|------|------|--------|
| **네트워크 접근** | K8s Worker Node → GitLab Registry 네트워크 경로가 열려있는지 확인 필요 | 🔴 |
| **인증** | GitLab Registry는 인증 필요 (Docker login) | 🔴 |
| **방화벽/포트** | 포트 10003 비표준, 외부 방화벽 차단 가능성 | 🔴 |
| **이미지 안정성** | `:latest` 태그 사용 → 버전 고정 필요 | 🟡 |

### 3.3 해결 방안 (2가지)

#### Option A: Harbor에 AIPP 전용 프로젝트 생성 (권장) ✅

이미지를 Harbor로 한 번 미러링해두면 이후 K8s Pull은 내부 네트워크로 해결:

```bash
# 1. 로컬에서 GitLab Registry 로그인 & Pull
docker login registry.gitlab.enai-rnd-2.en-core.info:10003
docker pull registry.gitlab.enai-rnd-2.en-core.info:10003/enai/prod/backend:latest

# 2. Harbor에 태그 변경 & Push
docker tag registry.gitlab.enai-rnd-2.en-core.info:10003/enai/prod/backend:latest \
  harbor.dev.unifiedmeta.net/aipp/backend:v1.0.0

docker push harbor.dev.unifiedmeta.net/aipp/backend:v1.0.0

# 모든 AIPP 이미지에 대해 반복:
#   - aipp/front-next:v1.0.0
#   - aipp/backend:v1.0.0
#   - aipp/catalog-collector:v1.0.0
#   - aipp/linker:v1.0.0
#   - aipp/scheduler:v1.0.0
```

**장점**: 내부 네트워크 완결, 버전 태깅 가능, Harbor 취약점 스캔  
**조건**: Harbor에 `aipp` 프로젝트 생성 필요

#### Option B: GitLab Registry 직접 Pull (imagePullSecret)

```yaml
# K8s에서 GitLab Registry 인증 시크릿 생성
kubectl create secret docker-registry gitlab-registry \
  --namespace=aipp \
  --docker-server=registry.gitlab.enai-rnd-2.en-core.info:10003 \
  --docker-username=<username> \
  --docker-password=<token>
```

**단점**: Worker Node → 외부 네트워크 의존, 자격증명 관리 부담

### 3.4 미러링 대상 이미지 목록

```
# 소스(GitLab)                                              → Harbor 타겟
registry.gitlab...10003/enai/prod/front-next:latest         → harbor.dev.unifiedmeta.net/aipp/front-next:v1.0.0
registry.gitlab...10003/enai/prod/backend:latest            → harbor.dev.unifiedmeta.net/aipp/backend:v1.0.0
registry.gitlab...10003/enai/prod/catalog-collector:latest  → harbor.dev.unifiedmeta.net/aipp/catalog-collector:v1.0.0
registry.gitlab...10003/enai/prod/linker:main-latest        → harbor.dev.unifiedmeta.net/aipp/linker:v1.0.0
registry.gitlab...10003/enai/prod/scheduler:latest          → harbor.dev.unifiedmeta.net/aipp/scheduler:v1.0.0
```

---

## 4. 인프라 활용 전략

### 4.1 기존 클러스터 컴포넌트 재활용

| AIPP 요구사항 | 기존 클러스터 | 활용 방식 |
|--------------|-------------|----------|
| Observability Stack | Prometheus + Grafana + Loki + Tempo | **별도 배포 안 함** — OTel 연동 |
| 영속 스토리지 | Longhorn | PVC `storageClassName: longhorn` |
| 시크릿 관리 | Vault | Vault Agent Sidecar 또는 External Secrets |
| TLS 인증서 | cert-manager (DNS-01) | Ingress 어노테이션으로 자동 발급 |
| DNS | external-dns | Ingress 기반 자동 등록 |
| 이미지 저장소 | Harbor | 미러링된 AIPP 이미지 사용 |

### 4.2 GPU 노드 요구사항

`enai-linker`는 NVIDIA GPU가 필수:

- **필요**: NVIDIA Device Plugin DaemonSet
- **노드**: GPU 인스턴스 (예: `g4dn.xlarge` 이상)
- **K8s 리소스 요청**: `nvidia.com/gpu: 1`
- **공유 메모리**: `/dev/shm` → `emptyDir` (medium: Memory)

> ⚠️ GPU 노드가 없으면 `enai-linker`를 제외하고 나머지 서비스만 우선 배포 가능

---

## 5. K8s 매니페스트 구조 (생성 예정)

```
gitops-apps/apps/aipp/
├── package/                    # 원본 Docker Compose (참조용)
└── k8s/
    └── base/
        ├── kustomization.yaml  # Kustomize 엔트리포인트
        ├── namespace.yaml      # aipp namespace
        ├── configmaps.yaml     # pg-init, linker config
        ├── secrets.yaml        # 인증 정보 (Vault 연동)
        ├── pgvector.yaml       # StatefulSet + PVC + Service
        ├── redis.yaml          # Deployment + PVC + Service
        ├── rabbitmq.yaml       # StatefulSet + PVC + Service
        ├── enai-backend.yaml   # Deployment + Service
        ├── enai-data-processor.yaml
        ├── enai-linker.yaml    # Deployment (GPU) + Service
        ├── enai-scheduler.yaml # Deployment + Service
        ├── enai-front.yaml     # Deployment + Service
        └── ingress.yaml        # TLS Ingress
```

ArgoCD Application: `gitops-apps/bootstrap/aipp.yaml`

---

## 6. 배포 단계별 실행 계획

### Phase 1: 사전 준비

1. Harbor에 `aipp` 프로젝트 생성
2. GitLab Registry 이미지 → Harbor 미러링 (5개 이미지)
3. GPU 노드 유무 확인 → 없으면 enai-linker 제외 계획
4. Vault에 AIPP 시크릿 경로 생성 (`secret/aipp/*`)

### Phase 2: K8s 매니페스트 작성

1. Namespace + ConfigMap + Secret
2. Infrastructure StatefulSets (pgvector, redis, rabbitmq)
3. Application Deployments (backend → processor/linker/scheduler → front)
4. Ingress + TLS

### Phase 3: ArgoCD 등록 및 배포

1. `bootstrap/aipp.yaml` ArgoCD Application 생성
2. Git push → ArgoCD 자동 sync
3. Sync Wave 순서 검증

### Phase 4: 검증

1. 전 Pod Running/Ready 확인
2. Health check 엔드포인트 테스트
3. DB 초기화 (pgvector extension) 확인
4. Frontend 웹 UI 접근 테스트
5. Grafana에서 AIPP 메트릭/로그 조회

---

## 7. 리스크 매트릭스

| 리스크 | 확률 | 영향 | 대응 |
|--------|------|------|------|
| GPU 노드 부재 | 높음 | linker 배포 불가 | linker 제외 → 별도 GPU 인스턴스 계획 |
| GitLab Registry 접근 불가 | 중간 | 이미지 Pull 실패 | Harbor 미러링으로 해결 |
| Linker 메모리 OOM | 중간 | Pod CrashLoop | resources limits 조정 |
| DB 초기화 Race condition | 낮음 | backend 기동 실패 | init container 재시도 로직 |

---

## 8. 체크리스트

### 사전 준비
- [ ] Harbor에 `aipp` 프로젝트 생성
- [ ] GitLab Registry 접근 가능 여부 확인
- [ ] 5개 커스텀 이미지 Harbor 미러링
- [ ] GPU 노드 현황 확인
- [ ] Vault 시크릿 경로 생성

### K8s 배포
- [ ] K8s 매니페스트 작성 (kustomize)
- [ ] ArgoCD Application YAML 생성
- [ ] Git push → sync 확인
- [ ] 전 Pod Healthy 확인

### 검증
- [ ] Health check 통과
- [ ] DB pgvector extension 확인
- [ ] Frontend 접근 테스트
- [ ] Observability 연동 확인 (선택)
