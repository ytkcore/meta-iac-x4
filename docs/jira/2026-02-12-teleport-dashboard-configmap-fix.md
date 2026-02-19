# Teleport 앱 이름 정리 + Dashboard ConfigMap 배포 수정

> **Status**: ✅ 완료  
> **Priority**: High  
> **Labels**: `teleport`, `argocd`, `configmap`, `dashboard`, `bugfix`  
> **작업 기간**: 2026-02-12  
> **주요 커밋**: `91f0e37`, `7c844fe`, `8292db2`

---

## 📋 요약

Teleport 앱 display_name 업데이트 과정에서 발생한 이름 매핑 오류를 수정하고,
Platform Dashboard가 ArgoCD OutOfSync 상태에서 영구 동기화 실패하는 문제의 근본 원인을 진단하여 해결.

---

## 🎯 목표

1. Teleport 앱 이름 `unified-meta-*` 패턴을 home/dashboard/opstart 3개에만 적용
2. 나머지 9개 앱은 원래 이름(argocd, grafana 등) 유지
3. Stale app_server 엔트리 제거
4. Dashboard 세로형 레이아웃 배포 — ArgoCD 영구 OutOfSync 문제 해결

---

## 📂 변경 파일

| 파일 | 변경 |
|:-----|:-----|
| `modules/access-gateway/teleport/main.tf` | [MOD] `name` 필드: `display_name` → `name` 매핑 복구 (`unified-meta-*` 패턴 유지) |
| `stacks/dev/80-access-gateway/variables.tf` | [MOD] home/dashboard/opstart에만 `unified-meta-*` display_name, 전체 앱에 한국어 description 추가 |
| `gitops-apps/bootstrap/platform-dashboard.yaml` | [MOD] `syncOptions`에 `ServerSideApply=true` 추가 |

---

## 🔍 근본 원인 분석 (2건)

### 1. Teleport 앱 이름 매핑 오류

- **증상**: Teleport UI에 중복 앱 엔트리 (old name + new name 동시 표시)
- **원인**: `main.tf`의 `name` 필드 로직 변경 시 `display_name → name` 매핑을 제거하여, `unified-meta-*` 패턴 대신 원래 `svc.name`이 사용됨
- **수정**: 
  - `name = svc.display_name != "" ? svc.display_name : svc.name` 원복
  - `unified-meta-*` display_name은 home/dashboard/opstart 3개에만 적용
  - 나머지 9개 앱은 display_name 제거 → 원래 이름 유지
- **Stale 정리**: `tctl rm app_server/{name}` 명령으로 총 21개 stale 엔트리 제거

### 2. Dashboard ArgoCD 영구 OutOfSync — ConfigMap annotation 크기 초과

- **증상**: ArgoCD sync 요청 후에도 영원히 OutOfSync 상태, 대시보드 변경사항(세로형 레이아웃) 미반영
- **원인**:
  - `platform-dashboard-html` ConfigMap에 HTML/CSS/JS/PNG 7개 파일 포함 → 데이터 크기 ~300KB
  - `kubectl apply`는 `kubectl.kubernetes.io/last-applied-configuration` annotation에 원본 매니페스트 전체를 저장
  - annotation 크기 제한: **262,144 bytes (256KB)** → 초과하여 apply 거부
  - ArgoCD도 내부적으로 `kubectl apply`를 사용 → 같은 이유로 sync 실패 → 영구 OutOfSync
- **수정**:
  - 즉시 해결: `kubectl apply --server-side --force-conflicts` 로 ConfigMap 직접 갱신
  - 영구 해결: ArgoCD Application에 `ServerSideApply=true` syncOption 추가
  - Server-Side Apply는 annotation 대신 K8s API 서버의 자체 필드 관리(managedFields)를 사용하여 크기 제한 없음

---

## ✅ 작업 내역

- [x] **1.1** `main.tf` — `display_name → name` 매핑 로직 복구
- [x] **1.2** `variables.tf` — home/dashboard/opstart에만 `unified-meta-*` display_name 적용
- [x] **1.3** `variables.tf` — 전체 12개 앱에 한국어 description 추가
- [x] **1.4** Terraform apply 반영 (SSM Parameter + Teleport 재시작)
- [x] **1.5** Stale app_server 엔트리 제거 (tctl rm)
- [x] **2.1** Dashboard ConfigMap 크기 초과 원인 진단
- [x] **2.2** `kubectl apply --server-side` 로 ConfigMap 강제 갱신
- [x] **2.3** ArgoCD Application에 `ServerSideApply=true` 영구 적용
- [x] **2.4** 새 Pod 생성 확인 (rollout restart)

---

## 📊 최종 상태

### Teleport 앱 목록 (15개)

```
EC2 (3):     harbor, neo4j, opensearch
K8s (9):     argocd, grafana, longhorn, rancher, vault,
             keycloak-admin, alertmanager, prometheus, aipp
K8s (3):     unified-meta-opstart, unified-meta-home, unified-meta-dashboard
```

### Dashboard

```
Pod                                   Ready  Age
platform-dashboard-57f8899967-r9nxd   1/1    Running  ✅ (신규 ConfigMap 적용)
platform-dashboard-57f8899967-xdpwv   1/1    Running  ✅ (신규 ConfigMap 적용)

ArgoCD syncOptions: ServerSideApply=true ✅
```

---

## 🔗 관련 티켓

- [teleport-app-service-completion](2026-02-09-teleport-app-service-completion.md) — Teleport App Service 초기 구축
- [customer-services-deployment](2026-02-10-customer-services-deployment.md) — Dashboard 초기 배포
- [argocd-drift-fix](2026-02-08-argocd-drift-fix.md) — ArgoCD OutOfSync 이전 사례

---

## 📝 비고

- **ConfigMap 크기 제한 교훈**: Static HTML 사이트를 ConfigMap으로 배포할 때, 전체 파일 크기가 **128KB를 넘으면** (annotation 복사본 포함 시 256KB 초과) 반드시 `ServerSideApply=true` 필요
- **향후 대안**: 대시보드가 더 커지면 ConfigMap 대신 **컨테이너 이미지 빌드**(Dockerfile + Harbor)로 전환 검토
- **Teleport stale 엔트리**: 앱 이름 변경 시 이전 이름의 heartbeat가 캐시에 남음. `tctl rm app_server/{old_name}`으로 즉시 제거 가능
