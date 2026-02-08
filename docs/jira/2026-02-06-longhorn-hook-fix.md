# [INFRA] Longhorn Pre-upgrade Hook 수정 — ServiceAccount Race Condition 해결

## 📋 Summary

ArgoCD에서 Longhorn 앱이 **OutOfSync + Missing** 상태로 고착되는 문제를 해결한다.
Helm pre-upgrade hook이 ServiceAccount 생성 전에 실행되어 Job이 실패하는
**race condition**을 disabled hook 설정으로 해결한다.

## 🎯 Goals

1. Longhorn ArgoCD App → Synced + Healthy 상태 확보
2. Pre-upgrade hook 비활성화로 race condition 제거
3. ArgoCD 자동 sync 안정화

## 📊 문제 원인

```
ArgoCD sync 시작
  → Helm pre-upgrade hook Job 실행
    → Job이 ServiceAccount를 참조
      → ServiceAccount가 아직 생성되지 않음 (race condition)
        → Job 실패 → Hook 실패 → Sync 실패
          → OutOfSync + Missing 상태 고착
```

## 📋 Tasks (완료)

- [x] Longhorn Helm values에 `preUpgrade.jobEnabled: false` 설정
- [x] ArgoCD sync retry 확인
- [x] Longhorn Pod 전체 정상 동작 확인

## 🔧 주요 변경 파일

| 파일 | 작업 |
|------|------|
| `gitops-apps/bootstrap/longhorn.yaml` | ✏️ `preUpgrade.jobEnabled: false` |

## 📎 References

- [Longhorn GitHub Issue #5958](https://github.com/longhorn/longhorn/issues/5958)

## 🏷️ Labels

`longhorn`, `argocd`, `bugfix`

## 📌 Priority / Status

**Medium** / ✅ 완료 (2026-02-06)
