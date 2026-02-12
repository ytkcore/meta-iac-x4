# AIPP K8s 매니페스트 + ArgoCD Application 등록

> **Status**: ✅ 완료  
> **Priority**: High  
> **Labels**: `aipp`, `k8s`, `argocd`, `gitops`, `microservices`  
> **작업 기간**: 2026-02-11  
> **주요 커밋**: `a7d69e7`

---

## 📋 요약

AI Integration & Processing Pipeline (AIPP) 서비스를 Kubernetes에 배포하기 위한
전체 매니페스트를 작성하고 ArgoCD Application으로 등록.
마이크로서비스 아키텍처 기반 9개 컴포넌트의 K8s 리소스를 정의.

---

## 🎯 목표

1. AIPP 전체 마이크로서비스 K8s 매니페스트 작성
2. ArgoCD Application 등록 (GitOps 자동 배포)
3. Namespace 분리 + Kustomization 구성

---

## 📂 변경 파일 (14 files, +1,031 lines)

| 파일 | 변경 |
|:-----|:-----|
| `gitops-apps/apps/aipp/k8s/namespace.yaml` | [NEW] aipp namespace |
| `gitops-apps/apps/aipp/k8s/backend.yaml` | [NEW] Backend Deployment + Service (163 lines) |
| `gitops-apps/apps/aipp/k8s/frontend.yaml` | [NEW] Frontend Deployment + Service + Ingress (108 lines) |
| `gitops-apps/apps/aipp/k8s/linker.yaml` | [NEW] Linker Service (135 lines) |
| `gitops-apps/apps/aipp/k8s/data-processor.yaml` | [NEW] Data Processor (124 lines) |
| `gitops-apps/apps/aipp/k8s/scheduler.yaml` | [NEW] Scheduler (84 lines) |
| `gitops-apps/apps/aipp/k8s/pgvector.yaml` | [NEW] PGVector DB — StatefulSet (151 lines) |
| `gitops-apps/apps/aipp/k8s/rabbitmq.yaml` | [NEW] RabbitMQ — StatefulSet (88 lines) |
| `gitops-apps/apps/aipp/k8s/redis.yaml` | [NEW] Redis — StatefulSet (83 lines) |
| `gitops-apps/apps/aipp/k8s/secrets.yaml` | [NEW] Sealed Secret 참조 |
| `gitops-apps/apps/aipp/k8s/kustomization.yaml` | [NEW] Kustomize 구성 |
| `gitops-apps/bootstrap/aipp.yaml` | [NEW] ArgoCD Application |
| `makefiles/ssm.mk` | [MOD] SSM 타임아웃 확장 |

---

## 🏗️ 아키텍처 (9 컴포넌트)

```
┌─────────────────────────────────────────────┐
│                  AIPP Namespace              │
│                                              │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐  │
│  │ Frontend │  │ Backend  │  │  Linker   │  │
│  └────┬─────┘  └────┬─────┘  └─────┬─────┘  │
│       │              │              │        │
│  ┌────┴──────┐  ┌────┴──────┐  ┌────┴─────┐  │
│  │ Scheduler │  │Data Proc. │  │ RabbitMQ │  │
│  └───────────┘  └───────────┘  └──────────┘  │
│                                              │
│  ┌──────────┐  ┌──────────┐                  │
│  │ PGVector │  │  Redis   │                  │
│  │ (State)  │  │ (Cache)  │                  │
│  └──────────┘  └──────────┘                  │
└─────────────────────────────────────────────┘
```

---

## ✅ 작업 내역

- [x] **1.1** AIPP namespace 정의
- [x] **1.2** 5개 애플리케이션 서비스 매니페스트 (Frontend, Backend, Linker, Data Processor, Scheduler)
- [x] **1.3** 3개 인프라 서비스 매니페스트 (PGVector, RabbitMQ, Redis)
- [x] **1.4** Secrets 참조 + Kustomization
- [x] **1.5** ArgoCD Application 등록
- [x] **1.6** SSM 타임아웃 확장 (make ssm 대응)

---

## 🔗 관련 티켓

- [opstart-k8s-deployment](2026-02-11-opstart-k8s-deployment.md) — OpStart 배포 (유사 패턴)
- [harbor-dns-s3-fix](2026-02-11-harbor-dns-s3-fix.md) — Harbor 이미지 저장소 수정

---

## 📝 비고

- AIPP는 마이크로서비스 아키텍처로, 서비스 간 RabbitMQ 메시지 큐 + Redis 캐시 패턴 사용
- PGVector는 벡터 DB (AI/ML 임베딩 저장)
- Harbor 이미지 빌드/푸시 후 ArgoCD Sync로 배포 예정
- Post-deploy: Harbor에 AIPP 이미지 5개 push 필요
