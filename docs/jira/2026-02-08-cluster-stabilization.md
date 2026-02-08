# [INFRA] 클러스터 안정화 — CCM 정리 + Monitoring Synced + Internal 전환 + Vault 검토

## 📋 Summary

클러스터 감사 결과 발견된 안정화 항목 4건을 처리. **13/13 ArgoCD 앱 Synced + Healthy** 달성.
CCM 정리, Monitoring 5-blocker 해결, Ingress Internal 전환, Vault HA 로드맵 문서화.

커밋: `ffda789` → `1173359` → `62e4e39` → `b9f676c` → `3cc6f30` → `5fa28e5` → `18ae624` → `2452fd4` → `a639e8f`

## 🎯 Goals

1. **T1**: CCM helm-install CrashLoopBackOff 제거 (970+ 재시작)
2. **T2**: Monitoring Prometheus OutOfSync → **완전 Synced** 달성
3. **T3**: Grafana/Vault Ingress → Internal NLB (Public 노출 차단)
4. **T4**: Vault HA 전환 로드맵 문서화

## 📊 진행 결과

### T1: CCM CrashLoopBackOff 정리 ✅
| 항목 | 결과 |
|------|------|
| HelmChart CR | ✅ 삭제 (`helm.cattle.io/v1 aws-cloud-controller-manager`) |
| Addon | ✅ 삭제 (`k3s.cattle.io/v1 aws-ccm`) |
| CrashLoop Pod | ✅ 강제 삭제 |
| 서버 매니페스트 | ✅ SSM 비활성화 (3 CP 노드 전부 `.disabled`) |

### T2: Monitoring OutOfSync → Synced ✅ (5-Blocker 해결)

| # | Blocker | 원인 | Fix | Commit |
|---|---------|------|-----|--------|
| 1 | Webhook TLS 실패 | `patch.enabled: false` → caBundle 비어있음 | `admissionWebhooks.enabled: false` | `3cc6f30` |
| 2 | Prometheus CRD 검증 | `retentionSize: 20Gi` regex 불일치 | `20GiB` | `5fa28e5` |
| 3 | PVC 교체 실패 | `Replace=true` + PVC immutable | 제거 + ignoreDiff | `18ae624` |
| 4 | Webhook 경고 잔존 | ArgoCD conditions 캐싱 | JSON patch 클리어 | — |
| **5** | **영구 OutOfSync** | **`valuesObject` → `RawExtension` 파싱 에러** | **`values` string 변환** | `2452fd4` |

> **Root Cause**: ArgoCD CRD의 `valuesObject` (inline YAML)가 `RawExtension`으로 역직렬화될 때,
> Helm chart 필드명(`prometheusOperator`, `grafana`)이 Go struct에 없어 status patch 실패 → `reconciledAt` 갱신 불가 → 영구 OutOfSync.

### T3: 관리 도구 Ingress Internal 전환 ✅
| 서비스 | 변경 | 상태 |
|--------|------|------|
| Grafana | `nginx` → `nginx-internal` | ✅ Internal NLB |
| Vault | `nginx` → `nginx-internal` | ✅ Internal NLB |

### T4: Vault 보안 강화 (검토) ✅
| 항목 | 결과 |
|------|------|
| 현재 구성 | Standalone, File storage, Shamir 5/3, 1 replica |
| HA 로드맵 | Phase A: AWS KMS Auto-Unseal → Phase B: Raft HA → Phase C: TLS E2E |
| Dev 판단 | 현재 유지, Phase A 우선 권장 |

## 📋 Tasks

- [x] T1: CCM HelmChart/Addon/Pod/매니페스트 정리
- [x] T2-1: admissionWebhooks 비활성화
- [x] T2-2: retentionSize 20GiB 수정
- [x] T2-3: PVC ignoreDifferences + Replace=true 제거
- [x] T2-4: ArgoCD conditions 캐시 클리어
- [x] T2-5: valuesObject → values string 변환 (Root Cause)
- [x] T3: Grafana/Vault ingressClassName nginx-internal 전환
- [x] T3: nginx-internal IngressClass 생성
- [x] T4: Vault HA 전환 로드맵 문서화
- [x] 13/13 ArgoCD 앱 Synced + Healthy 확인

## 🔧 주요 변경 파일

| 범주 | 파일 |
|------|------|
| GitOps | `gitops-apps/bootstrap/monitoring.yaml` — values string 변환 + 5-blocker fix |
| GitOps | `gitops-apps/bootstrap/vault.yaml` — ingressClassName |
| GitOps | `gitops-apps/bootstrap/nginx-ingress-internal.yaml` — IngressClass 분리 |
| Docs | `docs/vault/vault-ha-transition-roadmap.md` — HA 전환 3-Phase 로드맵 |

## 📎 References

- [Vault HA 로드맵](../vault/vault-ha-transition-roadmap.md)

## 🏷️ Labels

`ccm`, `monitoring`, `security`, `ingress`, `vault`, `stabilization`

## 📌 Priority / Status

**High** / ✅ 완료 (2026-02-08)
