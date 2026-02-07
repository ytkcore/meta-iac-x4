# Bridge Strategy — AWS 활용 → CSP-Agnostic 점진 전환

**작성일**: 2026-02-07  
**관련**: [platform-identity-architecture.md](platform-identity-architecture.md) (최종 목표 아키텍처)

---

## 1. 전략 개요

현재 AWS 기반 인프라를 활용하여 **빠르게 가치를 실현**하면서,  
추상화 레이어를 통해 **향후 CSP-Agnostic 전환 경로를 확보**하는 접근.

```
현재:     Pod ──직접──→ AWS API (Node IAM)

Bridge:   Pod ──→ [추상화 레이어] ──→ AWS API (지금)
                                  ──→ GCP API (나중에)
                                  ──→ 온프렘    (나중에)
```

> **핵심 차이**:  
> Strategy A (Full) = "완성되기 전까지 가치 없음"  
> Strategy B (Bridge) = **"매 단계마다 즉시 가치"**

---

## 2. 컴포넌트별 Bridge → 최종 전환 경로

| 기능 | Now (AWS Fast) | 추상화 레이어 | Later (CSP-Agnostic) | 교체 난이도 |
|------|---------------|-------------|---------------------|-----------|
| **사용자 인증** | 서비스별 개별 | — | **Keycloak** SSO | — |
| **NLB Target** | Node IAM + ALBC | — | SPIRE + ALBC | 낮음 |
| **시크릿** | AWS Secrets Manager | **ESO** | **Vault** | **매우 낮음** |
| **Pod → AWS** | Node IAM Role | — | **SPIRE** SVID | 중간 |
| **LB annotation** | `aws-*` annotations | **CSP values overlay** | CSP별 values 파일 | 낮음 |
| **인증서** | cert-manager (DNS-01) | 이미 추상화 ✅ | 동일 | — |
| **DNS** | external-dns (Route53) | 이미 추상화 ✅ | provider 변경만 | — |

---

## 3. 핵심 추상화 레이어 2개

### 3.1 External Secrets Operator (ESO)

```yaml
# 지금: AWS Secrets Manager
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
spec:
  provider:
    aws:
      service: SecretsManager
      region: ap-northeast-2
---
# 나중에: Vault (이것만 바꾸면 됨)
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
spec:
  provider:
    vault:
      server: "https://vault.unifiedmeta.net"
      path: "secret"
      auth:
        kubernetes: {}
```

- Pod 코드 변경: **없음**
- K8s 설정 변경: `SecretStore` CR의 `provider`만 변경

### 3.2 CSP Values Overlay (nginx-ingress)

```
gitops-apps/bootstrap/nginx-ingress-internal.yaml  ← 공통
gitops-apps/overlays/aws/nginx-ingress-values.yaml ← AWS 전용 annotations
gitops-apps/overlays/gcp/nginx-ingress-values.yaml ← GCP 전용 (나중에)
gitops-apps/overlays/bare/nginx-ingress-values.yaml ← 온프렘 MetalLB (나중에)
```

---

## 4. Phase별 일정

### Phase B-1: 즉시 해결 (ALBC + Node IAM) — 2일

| 일차 | 작업 | 효과 |
|------|------|------|
| D1 | ALBC Helm 배포 (Node IAM 방식) | NLB Target 자동 관리 |
| D2 | nginx-ingress annotation → IP mode + 검증 | **CCM 버그 근본 해결** |

### Phase B-2: ESO + AWS Secrets Manager — 2일

| 일차 | 작업 | 효과 |
|------|------|------|
| D3 | ESO Helm 배포 + AWS SM SecretStore 설정 | 시크릿 추상화 레이어 확보 |
| D4 | 기존 K8s Secrets → ExternalSecret CR 전환 | **Vault 전환 준비 완료** |

### Phase B-3: Keycloak (SSO) — 5일

| 일차 | 작업 | 효과 |
|------|------|------|
| D5 | `25-keycloak` Terraform 스택 배포 | Keycloak 동작 |
| D6 | Realm/Client 구성 + Grafana SSO | 첫 SSO 서비스 |
| D7 | ArgoCD + Rancher SSO | 3개 서비스 SSO |
| D8 | Harbor + Teleport SSO | **5개 서비스 SSO 완성** |
| D9 | K8s API OIDC + 통합 테스트 | kubectl SSO 로그인 |

### Phase B-4: SPIRE (Node IAM 대체) — 5일

| 일차 | 작업 | 효과 |
|------|------|------|
| D10 | SPIRE Server/Agent 배포 | Workload ID 기반 |
| D11 | AWS STS Federation 연동 | Node IAM 대체 |
| D12 | ALBC → SPIRE 인증 전환 | **Pod별 IAM 분리** |
| D13 | CSP overlay 구조 적용 | LB annotation 추상화 |
| D14 | CCM 제거 + 통합 테스트 | **AWS K8s 의존성 제거** |

### Phase B-5: Vault (ESO 백엔드 교체) — 3일

| 일차 | 작업 | 효과 |
|------|------|------|
| D15 | Vault Helm 배포 (HA) | Vault 동작 |
| D16 | ESO SecretStore → Vault provider | **백엔드 교체 (Pod 변경 없음)** |
| D17 | DB dynamic secrets + 문서 | **4-Layer 완성** |

---

## 5. 일정 비교 (Strategy A vs B)

| 전략 | MVP | Standard | Full | 리스크 |
|------|-----|----------|------|--------|
| **A: Full CSP-Agnostic** | 1주 | 2주 | 3~4주 | SPIRE 실패 시 전체 블로킹 |
| **B: Bridge** | **2일** | 1주 | **2~3주** | 각 Phase 독립 동작 |

### Phase별 독립성

```
B-1 완료 → NLB 자동화 OK. 여기서 멈춰도 됨.
B-2 완료 → 시크릿 추상화 OK. 여기서 멈춰도 됨.
B-3 완료 → SSO OK. 여기서 멈춰도 됨.
B-4 완료 → CSP 무관 OK. 여기서 멈춰도 됨.
B-5 완료 → 4-Layer 완성. = Strategy A 최종 형상과 동일.
```

---

## 6. 리스크

| 리스크 | 영향 | Bridge 대응 |
|--------|------|------------|
| SPIRE + AWS STS 복잡도 | +2~3일 | B-1/B-2/B-3는 SPIRE 없이 동작 |
| Keycloak DB 의존 | 배포 순서 | 60-postgres 선행 필수 |
| NLB 재생성 다운타임 | 수 분 | 유지보수 윈도우 지정 |
| ESO → Vault 전환 | 낮음 | SecretStore CR만 변경 |
