# T2: Monitoring OutOfSync → Synced (5-Blocker 해결)

> **Parent**: [클러스터 안정화](../2026-02-08-cluster-stabilization.md) | **Status**: ✅ 완료

## 📋 Summary

ArgoCD `monitoring` 앱(kube-prometheus-stack)이 영구 OutOfSync 상태에 빠진 근본 원인을 추적하여 5개의 연쇄 Blocker를 순차 해결. 최종적으로 **완전 Synced + Healthy** 달성.

## 🔍 문제

```
monitoring    OutOfSync    Degraded
```

ArgoCD sync를 반복해도 항상 OutOfSync로 복귀. Prometheus Pod CrashLoop + Webhook 실패가 중첩.

## 🔧 5-Blocker 해결 과정

### Blocker 1: Admission Webhook TLS 실패
**증상**: `kube-prometheus-stack-admission` webhook이 TLS 인증서 없이 생성되어 모든 PrometheusRule CRD 검증 실패.

**원인**: `admissionWebhooks` 생성 시 cert-manager 의존성 충돌.

**Fix**:
```yaml
# monitoring.yaml
prometheus:
  prometheusSpec:
    ruleSelectorNilUsesHelmValues: false
kube-prometheus-stack:
  admissionWebhooks:
    enabled: false    # ← TLS 없이 webhook 생성 방지
```

**커밋**: `3cc6f30`

---

### Blocker 2: Prometheus CRD 검증 오류
**증상**: `retentionSize` 필드가 CRD validation에 실패 → Prometheus Pod 시작 불가.

**원인**: `retentionSize` 값에 단위 표기가 CRD spec과 불일치 (`GiB` vs `GB`).

**Fix**:
```yaml
prometheusSpec:
  retentionSize: "20GiB"    # ← 이진 단위(GiB) 사용
```

**커밋**: `5fa28e5`

---

### Blocker 3: PVC 교체 실패 (StorageClass 불일치)
**증상**: Prometheus PVC가 기존 `local-path` StorageClass로 생성되어 있으나, 새 values에서 `longhorn` 요청 → PVC 교체 불가.

**원인**: ArgoCD sync 시 PVC는 immutable field이므로 `Replace=true` + `ignoreDifferences`로 우회 시도했으나 부작용 발생.

**Fix**: `Replace=true` 제거 + 기존 PVC 유지 전략. `ignoreDifferences`에서 PVC 관련 diff 제외.

**커밋**: `18ae624`

---

### Blocker 4: Webhook 경고 잔존
**증상**: Blocker 1 수정 후에도 이전에 생성된 webhook failure 관련 경고가 ArgoCD diff에 남아 OutOfSync 표시.

**Fix**: JSON patch로 잔존 경고 클리어.

---

### Blocker 5: 영구 OutOfSync (Root Cause) 🔑
**증상**: 모든 리소스가 정상임에도 ArgoCD가 영구적으로 OutOfSync 보고.

**근본 원인**: ArgoCD Application CR에서 `values`가 YAML object 형태(`valuesObject`)로 저장되어 있으나, ArgoCD의 diff 엔진이 이를 string으로 비교 → 항상 diff 발생.

**Fix**: `valuesObject` → `values` (string) 변환. ArgoCD Application CR의 `.spec.source.helm.values`를 multiline string으로 변환.

```yaml
# Before (ArgoCD가 object로 저장):
spec:
  source:
    helm:
      valuesObject:
        grafana:
          enabled: true
          ...

# After (string으로 변환):
spec:
  source:
    helm:
      values: |
        grafana:
          enabled: true
          ...
```

**커밋**: `2452fd4`

## ✅ 검증

```
monitoring    Synced    Healthy
```

- Prometheus 3/3 containers Running
- Grafana 3/3 containers Running
- Alertmanager Ready
- 모든 ServiceMonitor 정상 수집

## 💡 Lessons Learned

1. **ArgoCD `valuesObject` vs `values`**: Helm values를 YAML object로 저장하면 ArgoCD의 diff 엔진이 올바르게 비교하지 못해 영구 OutOfSync 유발. 반드시 string(|) 형태로 저장.
2. **Webhook + cert-manager 의존성**: kube-prometheus-stack의 admission webhook은 cert-manager가 먼저 Ready여야 함. Race condition 시 비활성화가 안전.
3. **PVC immutability**: StorageClass 변경은 PVC 재생성 필요 → 운영 환경에서는 기존 PVC 유지 전략 권장.

## 🔧 변경 파일

| 파일 | 변경 | 커밋 |
|------|------|------|
| `gitops-apps/bootstrap/monitoring.yaml` | admissionWebhooks 비활성 | `3cc6f30` |
| `gitops-apps/bootstrap/monitoring.yaml` | retentionSize GiB | `5fa28e5` |
| `gitops-apps/bootstrap/monitoring.yaml` | ignoreDiff/Replace 제거 | `18ae624` |
| `gitops-apps/bootstrap/monitoring.yaml` | values string 변환 | `2452fd4` |

## 🏷️ Labels
`monitoring`, `argocd`, `prometheus`, `helm`, `troubleshooting`
