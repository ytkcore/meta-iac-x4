# [INFRA] CiliumNetworkPolicy Cross-namespace fromEndpoints 수정

## 📋 Summary

CiliumNetworkPolicy의 `fromEndpoints`에서 다른 namespace의 Pod을 매칭할 때
`k8s:io.kubernetes.pod.namespace` label이 누락되어 **default-deny**가 적용,
Nginx Ingress → Keycloak Pod 통신이 차단되던 문제 수정.

## 🎯 Root Cause

```yaml
# 수정 전 — namespace 미지정 → Cilium이 매칭 실패 → default-deny
fromEndpoints:
  - matchLabels:
      app.kubernetes.io/name: ingress-nginx        # namespace 불명확

# 수정 후 — cross-namespace 매칭 정상
fromEndpoints:
  - matchLabels:
      k8s:io.kubernetes.pod.namespace: ingress-nginx  # ← 필수
      app.kubernetes.io/name: ingress-nginx
```

Cilium에서 `fromEndpoints`가 endpointSelector와 다른 namespace의 Pod을 매칭하려면
`k8s:io.kubernetes.pod.namespace` 지정이 **필수** (Cilium 공식 문서 명시).

## 📋 Tasks

- [x] **1.1** 진단: Public Ingress → Keycloak Pod curl timeout 확인
- [x] **1.2** CiliumNetworkPolicy 임시 삭제 시도 → ArgoCD selfHeal 자동 복원
- [x] **1.3** `resources.yaml` — Public/Internal 양쪽 `fromEndpoints`에 namespace label 추가
- [x] **1.4** Git push → ArgoCD sync → HTTP 200 확인

## 🔧 변경 파일

| 파일 | 변경 |
|------|------|
| `gitops-apps/keycloak-ingress/resources.yaml` | CNP `fromEndpoints`에 namespace label 추가 |

## 📎 Commits

| Hash | 설명 |
|------|------|
| `c255837` | CiliumNetworkPolicy cross-namespace 수정 |

## 💡 학습 포인트

- Cilium `fromEndpoints`: 같은 namespace Pod 매칭 시 namespace label 불필요
- **Cross-namespace**: `k8s:io.kubernetes.pod.namespace` 필수
- ArgoCD `selfHeal: true` 환경에서는 kubectl delete로는 정책 수정 불가 → 코드 수정 필수

## 🏷️ Labels

`cilium`, `network-policy`, `cross-namespace`, `bugfix`

## 📌 Priority / Status

**Critical** | ✅ **Done**
