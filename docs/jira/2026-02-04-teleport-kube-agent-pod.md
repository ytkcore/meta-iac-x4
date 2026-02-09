# Teleport Kube Agent Pod 배포

> **Status**: ✅ 완료  
> **Priority**: High  
> **Labels**: `teleport`, `kubernetes`, `gitops`, `access-control`  
> **적용일**: 2026-02-04  
> **커밋**: `63afa64` — `added teleport`

---

## 📋 요약

RKE2 클러스터에 **Teleport Kube Agent**를 K8s Pod으로 배포하여
`tsh kube` / `kubectl` 통합 접근 경로를 확보한다.
VPN → Teleport 전환 작업의 일환으로, EC2 Teleport Proxy를 거쳐
K8s API에 안전하게 접근할 수 있는 구조를 구축한다.

---

## 🎯 목표

1. Teleport Kube Agent Helm Chart를 ArgoCD Application으로 배포
2. `teleport-kube-agent` v17.0.0 기반 `roles: kube` 설정
3. Teleport Proxy (`teleport.dev.unifiedmeta.net:443`) 연동
4. `meta-dev` 클러스터명으로 등록 → `tsh kube ls` / `tsh kube login` 가능

---

## 📂 변경 파일

| 파일 | 변경 |
|:-----|:-----|
| `gitops-apps/platform/teleport-agent.yaml` | [NEW] ArgoCD Application 매니페스트 |

### teleport-agent.yaml 주요 설정

```yaml
source:
  repoURL: https://charts.releases.teleport.dev
  chart: teleport-kube-agent
  targetRevision: 17.0.0
  helm:
    values: |
      roles: "kube"
      proxyAddr: "teleport.dev.unifiedmeta.net:443"
      kubeClusterName: "meta-dev"
destination:
  namespace: teleport
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

---

## ✅ 작업 내역

- [x] **1.1** `teleport-agent.yaml` ArgoCD Application 작성
- [x] **1.2** Helm values 설정 (`roles: kube`, `proxyAddr`, `kubeClusterName`)
- [x] **1.3** ArgoCD 자동 Sync + namespace 자동 생성 구성
- [x] **2.1** 관련 운영 문서 작성 (조인 토큰 생성 절차 등)

---

## 🔗 관련 티켓 / 문서

- [teleport-ha-access-control](2026-02-04-teleport-ha-access-control.md) — 같은 날 배포된 Teleport HA 구조
- [golden-image-restructure](2026-02-04-golden-image-stack-restructure.md) — VPN→Teleport 전환 포함
- [teleport-operations-manual](../access-control/teleport-operations-manual.md) — Kube Agent 조인 토큰 운영 절차
- [golden-image-optimization-strategy](../access-control/golden-image-optimization-strategy.md) — Kube Agent Pod 전략

---

## 📝 비고

- 조인 토큰은 `teleport-kube-agent-join-token` K8s Secret으로 관리 권장
- IAM Join 방식(`joinParams.method: iam`)도 지원 — 프로덕션에서는 IAM 방식 권장
- 이 커밋(`63afa64`)은 VPN 제거 + Teleport 전면 전환의 대규모 커밋(74 파일 변경)에 포함
