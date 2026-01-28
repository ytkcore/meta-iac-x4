# Rancher Installation Guide

## 📋 목차
- [개요](#개요)
- [글로벌 베스트 프랙티스](#글로벌-베스트-프랙티스)
- [설치 순서](#설치-순서)
- [사전 요구사항](#사전-요구사항)
- [설치 방법](#설치-방법)
- [설치 후 작업](#설치-후-작업)
- [Day 2 Operations](#day-2-operations)
- [트러블슈팅](#트러블슈팅)

---

## 개요

이 스택은 RKE2 클러스터에 Rancher를 설치합니다.

```
스택 적용 순서:
00-network → 10-security → 20-endpoints → 30-db → 40-bastion → 45-harbor → 50-rke2 → 55-rancher
```

---

## 글로벌 베스트 프랙티스

### 🎯 Terraform vs Helm/GitOps 선택 가이드

| 구분 | Terraform + Helm Provider | 순수 Helm/GitOps |
|------|---------------------------|------------------|
| **적합한 시나리오** | 초기 부트스트랩 (Day 1) | 운영/업그레이드 (Day 2) |
| **장점** | IaC 일관성, 재현성, 인프라와 통합 | 변경 추적, 롤백 용이, K8s 네이티브 |
| **단점** | Helm 업그레이드 복잡, State 관리 | 인프라와 분리됨 |
| **권장 사용처** | 인프라팀 주도 초기 구축 | 플랫폼팀 운영 |

### ✅ SUSE/Rancher 공식 권장사항

1. **설치**: Helm 차트를 통한 설치 (Terraform Helm Provider 포함)
2. **운영**: **Fleet** (Rancher 내장 GitOps) 또는 **ArgoCD** 활용
3. **업그레이드**: GitOps를 통한 선언적 업그레이드

### 🏗️ 권장 아키텍처 (성숙도 모델)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Phase 1: 초기 구축                                │
│                                                                             │
│   Terraform ─────► RKE2 Cluster ─────► Rancher (Helm Provider)              │
│                                                                             │
│   • 이 스택(55-rancher)이 담당                                              │
│   • 인프라와 함께 버전 관리                                                  │
│   • 재현 가능한 설치                                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                           Phase 2: 운영 성숙                                │
│                                                                             │
│   Git Repo ─────► Fleet/ArgoCD ─────► Rancher Upgrades                      │
│                                                                             │
│   • Helm values를 Git 저장소에서 관리                                        │
│   • PR 기반 변경 관리                                                       │
│   • 자동화된 롤백                                                           │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 설치 순서

### 1. 사전 요구사항 확인

```bash
# RKE2 클러스터 상태 확인
kubectl get nodes
kubectl get pods -A

# kubeconfig 설정 확인
kubectl config current-context
```

### 2. 변수 설정

```bash
cd stacks/dev/55-rancher
cp terraform.tfvars.example terraform.tfvars
vi terraform.tfvars
```

**필수 설정 항목:**
```hcl
# 도메인
domain = "your-domain.com"

# 초기 비밀번호 (반드시 변경!)
bootstrap_password = "YourSecurePassword123!"

# TLS 소스 선택
tls_source = "rancher"  # 또는 "letsEncrypt", "secret"
```

### 3. Terraform 적용

```bash
# 환경에 맞게 실행
make ENV=dev STACK=55-rancher plan
make ENV=dev STACK=55-rancher apply
```

### 4. 설치 확인

```bash
# Rancher Pod 상태 확인
kubectl get pods -n cattle-system

# cert-manager 상태 확인
kubectl get pods -n cert-manager

# Ingress 확인
kubectl get ingress -n cattle-system

# 인증서 상태 확인
kubectl get certificates -A
```

---

## 사전 요구사항

### 필수 조건

| 항목 | 요구사항 |
|------|----------|
| RKE2 클러스터 | 50-rke2 스택 적용 완료 |
| Kubernetes 버전 | v1.25 ~ v1.28 (Rancher 2.8.x 기준) |
| Worker 노드 | 최소 3개 (HA 구성) |
| 노드 리소스 | 각 노드 4GB+ RAM |
| Ingress Controller | nginx 또는 traefik |

### 네트워크 요구사항

| 포트 | 용도 |
|------|------|
| 443 | Rancher UI/API |
| 80 | HTTP → HTTPS 리다이렉트 |
| 6443 | Kubernetes API (내부) |

---

## 설치 후 작업

### 1. DNS 설정

```bash
# Ingress NLB DNS 확인
kubectl get svc -n ingress-nginx

# DNS 레코드 생성
# rancher.your-domain.com → NLB DNS
```

### 2. 초기 로그인 및 비밀번호 변경

1. `https://rancher.your-domain.com` 접속
2. 초기 비밀번호로 로그인
3. **즉시 비밀번호 변경**

### 3. 서버 URL 설정

```
Rancher UI > Global Settings > server-url
값: https://rancher.your-domain.com
```

### 4. 백업 설정

```
Rancher UI > Cluster Management > local > Backups
• S3 또는 PV에 백업 설정
• 백업 주기: 일 1회 이상 권장
```

---

## Day 2 Operations

### Option A: Rancher Fleet (권장)

Rancher에 내장된 GitOps 엔진입니다.

```yaml
# fleet.yaml 예시
defaultNamespace: cattle-system
helm:
  releaseName: rancher
  repo: https://releases.rancher.com/server-charts/stable
  chart: rancher
  version: 2.8.5
  values:
    hostname: rancher.your-domain.com
    replicas: 3
```

**설정 방법:**
1. Rancher UI > Continuous Delivery
2. Git Repos 추가
3. Helm values를 Git으로 관리

### Option B: ArgoCD

```yaml
# argocd-application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rancher
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://releases.rancher.com/server-charts/stable
    chart: rancher
    targetRevision: 2.8.5
    helm:
      values: |
        hostname: rancher.your-domain.com
        replicas: 3
  destination:
    server: https://kubernetes.default.svc
    namespace: cattle-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Terraform에서 GitOps로 전환

초기 설치 후 GitOps로 전환하려면:

```bash
# 1. Terraform state에서 Helm release 제거 (삭제하지 않음)
terraform state rm module.rancher.helm_release.rancher

# 2. GitOps 도구로 관리 전환
# Fleet 또는 ArgoCD에서 동일한 Helm 설정으로 관리
```

---

## 트러블슈팅

### Error: chart requires kubeVersion: < 1.29.0-0 (Kubernetes v1.33.x 등에서 발생)

증상:
- `chart requires kubeVersion: < 1.29.0-0 which is incompatible with Kubernetes v1.33.x ...`

원인:
- Rancher Helm chart 버전이 너무 오래된 경우(예: 2.8.x), Chart.yaml의 `kubeVersion` 제약으로 Helm이 설치를 차단합니다.

해결:
- Kubernetes v1.33.x 환경에서는 **Rancher chart 2.12+** 로 올리세요.
  - 예: `rancher_version = "2.13.1"`
- 또는(권장하지 않음) Rancher chart 버전에 맞춰 Kubernetes 버전을 낮추세요.



### cert-manager CRD 오류

```bash
# CRD 수동 설치
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.5/cert-manager.crds.yaml
```

### Rancher Pod가 시작되지 않음

```bash
# 로그 확인
kubectl logs -n cattle-system -l app=rancher --tail=100

# 이벤트 확인
kubectl get events -n cattle-system --sort-by='.lastTimestamp'
```

### 인증서 발급 실패

```bash
# Certificate 상태 확인
kubectl describe certificate -n cattle-system

# cert-manager 로그 확인
kubectl logs -n cert-manager -l app=cert-manager --tail=100
```

### Ingress 접근 불가

```bash
# Ingress 상태 확인
kubectl describe ingress -n cattle-system rancher

# Ingress Controller 로그 확인
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=100
```

---

## 참고 자료

- [Rancher 공식 문서](https://ranchermanager.docs.rancher.com)
- [cert-manager 공식 문서](https://cert-manager.io/docs/)
- [Rancher Fleet 문서](https://fleet.rancher.io/)
- [Rancher GitHub](https://github.com/rancher/rancher)


### External TLS Termination (NLB/ACM) 기본값

이 모듈은 RKE2 Public NLB에서 **ACM으로 TLS를 종료**하는 구성을 기본값으로 둡니다.

- `tls_source = "external"`
- `external_tls_termination = true`
- `skip_cert_manager = true`

즉, Rancher Ingress는 HTTP로 구성되고, 외부 HTTPS는 NLB(ACM)에서 처리합니다.


### certmanager.version 오버라이드 제거

Rancher chart의 `certmanager.version` 값은 **전달하지 않습니다**(차트 기본값 사용).
일부 환경에서 `cert-manager.io/v1alpha2` Issuer 렌더링 문제가 발생할 수 있어, 오버라이드를 제거해
차트가 클러스터 capability/CRD에 맞게 판단하도록 했습니다.


### Helm set 값 자동 타입 변환 주의 (annotations)

Helm provider의 `set`은 기본적으로 값 타입을 자동 추론합니다.
예: `"false"` → boolean `false`로 변환될 수 있어, Kubernetes `metadata.annotations`(string map)에서 오류가 날 수 있습니다.

본 모듈은 `ingress.extraAnnotations.*` 값에 `type = "string"`을 지정해 항상 문자열로 전달합니다.
