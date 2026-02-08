# [INFRA] ArgoCD OutOfSync Drift 수정 — ignoreDifferences 설정

## 📋 Summary

Vault, Longhorn, Monitoring ArgoCD 앱의 **OutOfSync** 상태를 해결한다.
Helm controller가 런타임에 주입하는 필드(defaultMode, resources, securityContext 등)와
Git 매니페스트 간의 차이를 `ignoreDifferences`로 무시 처리한다.

## 🎯 Goals

1. Vault, Longhorn, Monitoring 앱 → **Synced** 상태 달성
2. 런타임 필드 drift를 `ignoreDifferences`로 일괄 처리
3. ArgoCD 자동 sync 안정화

## 📊 Drift 원인 분석

```
Helm Chart 배포
  → K8s API Server가 defaultMode, resources 등을 자동 주입
    → Git 매니페스트와 live 상태 차이 발생
      → ArgoCD가 OutOfSync로 판단
        → 강제 sync 해도 즉시 다시 OutOfSync
```

**영향받는 리소스 타입**: Deployment, StatefulSet, DaemonSet

## 📋 Tasks (완료)

### 1차 수정
- [x] `vault.yaml` — Deployment/StatefulSet ignoreDifferences 추가
- [x] `longhorn.yaml` — Deployment ignoreDifferences 추가
- [x] `monitoring.yaml` — Prometheus/Grafana ignoreDifferences 추가

### 2차 확장
- [x] `spec/template/spec` 수준까지 범위 확대
- [x] StatefulSet, Deployment, DaemonSet 전체 적용

### 3차 최종
- [x] `spec/template/spec` 레벨 ignoreDifferences 통합
- [x] Pod-level 필드 (containers, initContainers, volumes) 포함

## 🔧 주요 변경 파일

| 파일 | 설정 |
|------|------|
| `gitops-apps/bootstrap/vault.yaml` | ✏️ ignoreDifferences 추가 |
| `gitops-apps/bootstrap/longhorn.yaml` | ✏️ ignoreDifferences 추가 |
| `gitops-apps/bootstrap/monitoring.yaml` | ✏️ ignoreDifferences 추가 |

## 📊 ignoreDifferences 패턴

```yaml
ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
      - /spec/template/spec/containers/0/resources
      - /spec/template/spec/securityContext
      - /spec/template/spec/volumes/0/projected/sources/0/configMap/items
  - group: apps
    kind: StatefulSet
    jsonPointers:
      - /spec/template/spec/containers/0/resources
      - /spec/volumeClaimTemplates/0/spec/volumeMode
```

## ⚠️ 알려진 잔존 사항

| 앱 | Sync | Health | 비고 |
|----|------|--------|------|
| vault | ⚠️ OutOfSync | ⬜ Missing | Ingress disabled 상태 |
| longhorn | ⚠️ 1 resource OutOfSync | ✅ Healthy | `longhorn-driver-deployer` |
| monitoring | ⚠️ 2 resources OutOfSync | ✅ Healthy | Grafana Deployment, Prometheus |

> 완전한 해결은 Cilium 전환(Phase 6) 후 클린 재배포 시 달성 예정

## 📎 References

- [ArgoCD Diffing Customization](https://argo-cd.readthedocs.io/en/stable/user-guide/diffing/)

## 🏷️ Labels

`argocd`, `drift`, `ignoreDifferences`, `bugfix`

## 📌 Priority / Status

**Medium** / 🔄 부분 완료 (2026-02-08)
