# [INFRA] 클러스터 안정화 — CCM 정리 + 관리 도구 Internal 전환

## 📋 Summary

클러스터 감사 결과 발견된 즉시 해결 가능한 안정화 항목 3건을 처리한다.
CCM CrashLoopBackOff 정리, Monitoring drift 해결, Grafana/Vault Public NLB 노출 차단.

커밋: `ffda789`

## 🎯 Goals

1. **T1**: CCM helm-install CrashLoopBackOff 제거 (970+ 재시작)
2. **T2**: Monitoring Prometheus OutOfSync drift 해결
3. **T3**: Grafana/Vault Ingress → Internal NLB (Public 노출 차단)

## 📊 진행 결과

### T1: CCM CrashLoopBackOff 정리 ✅
| 항목 | 결과 |
|------|------|
| HelmChart CR | ✅ 삭제 (`helm.cattle.io/v1 aws-cloud-controller-manager`) |
| Addon | ✅ 삭제 (`k3s.cattle.io/v1 aws-ccm`) |
| CrashLoop Pod | ✅ 강제 삭제 |
| 서버 매니페스트 | ⏳ SSM 수동 (mv aws-ccm.yaml .disabled) |

> **CCM은 RKE2 `cloud-provider-name=aws` 설정이 자동 생성.** Cilium 전환(Phase 6) 시 config 정리

### T2: Monitoring Prometheus OutOfSync 🔄
| 항목 | 결과 |
|------|------|
| ignoreDifferences | ✅ 이미 `.spec`, `.metadata.annotations` 포함 |
| Force sync 시도 | ✅ `Progressing` → `Healthy` (drift 지속) |
| 상태 | 🟡 Prometheus CRD spec drift — benign (Healthy) |

> **Known Issue**: kube-prometheus-stack의 Prometheus CR은 operator가 spec을 변형하여 ArgoCD와 영구 drift 발생. Healthy이므로 운영 영향 없음.

### T3: 관리 도구 Ingress Internal 전환 📝
| 서비스 | 변경 | 상태 |
|--------|------|------|
| Grafana | `nginx` → `nginx-internal` | ✅ Git 반영, ArgoCD sync 대기 |
| Vault | `nginx` → `nginx-internal` | ✅ Git 반영, ArgoCD sync 대기 |

> Git push 완료. ArgoCD selfHeal이 자동 적용 예정.

## 📋 Tasks

- [x] CCM HelmChart CR 삭제
- [x] CCM Addon 삭제
- [x] CCM CrashLoop Pod 강제 삭제
- [x] Monitoring ignoreDifferences 확인
- [x] Monitoring force sync 시도
- [x] Grafana ingressClassName `nginx` → `nginx-internal`
- [x] Vault ingressClassName `nginx` → `nginx-internal`
- [x] Git commit + push
- [ ] ArgoCD sync 완료 확인 (터널 재연결 후)
- [ ] Internal NLB 라우팅 확인

## ⚠️ 이슈

| # | Issue | Status |
|---|-------|--------|
| 1 | CCM 서버 매니페스트 제거 필요 | SSM 수동 작업 (기존 세션 활용) |
| 2 | Monitoring Prometheus 영구 drift | Known Issue — Healthy, 운영 영향 없음 |
| 3 | K8s API 터널 끊어짐 | 재연결 후 sync 확인 필요 |

## 🔧 주요 변경 파일

| 범주 | 파일 |
|------|------|
| GitOps | `gitops-apps/bootstrap/monitoring.yaml` — Grafana ingressClassName |
| GitOps | `gitops-apps/bootstrap/vault.yaml` — Vault ingressClassName |

## 📎 References

- [구현 계획](../../.gemini/antigravity/brain/7e05bd99-588e-407f-8ee3-54ce6da2b372/implementation_plan.md) — 클러스터 감사 결과

## 🏷️ Labels

`ccm`, `monitoring`, `security`, `ingress`, `stabilization`

## 📌 Priority / Status

**High** / 🔄 부분 완료 (2026-02-08)
