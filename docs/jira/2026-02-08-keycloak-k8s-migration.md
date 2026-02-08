# [INFRA] Keycloak EC2 → K8s-native 마이그레이션 — Dual Ingress + CiliumNetworkPolicy

## 📋 Summary

Cilium 클러스터 재구축 시점에 맞춰 Keycloak을 EC2(Docker Compose)에서 **K8s-native(Helm)**으로 전환한다.
글로벌 표준 패턴인 **Dual Ingress**(Public OIDC + Internal Admin)와 **CiliumNetworkPolicy L7**을 적용하여
OIDC 엔드포인트만 외부에 노출하고 Admin Console은 내부에서만 접근 가능하게 한다.

## 🎯 Goals

1. **K8s-native 배포**: EC2 의존 제거, ArgoCD GitOps 관리
2. **Dual Ingress**: Public(OIDC) + Internal(Admin) 트래픽 분리
3. **L7 NetworkPolicy**: HTTP path 수준 접근 제어 (Cilium 필수)
4. **HPA**: 자동 스케일링 (replicas: 2+)
5. **25-keycloak Terraform 스택 간소화**: EC2 관련 리소스 제거

## 📊 아키텍처

```
K8s Namespace: keycloak
├── Deployment: keycloak (replicas: 2, HPA)
│   ├── KC_HOSTNAME: keycloak.dev.unifiedmeta.net
│   ├── KC_HOSTNAME_ADMIN: keycloak-admin.dev.unifiedmeta.net
│   └── KC_PROXY: edge
├── Public Ingress (nginx-public)
│   └── OIDC endpoint → /.well-known/*, /realms/*
├── Internal Ingress (nginx-internal)
│   └── Admin Console → /admin/*
├── CiliumNetworkPolicy
│   ├── Public: OIDC path만 허용 (L7)
│   └── Admin: internal ingress에서만 허용
├── Service → ClusterIP
└── DB: 기존 60-postgres (외부 EC2)
```

## 📋 Tasks

### Phase 0: 사전 준비

- [ ] **0.1** Helm Chart 선정 (Bitnami keycloak or codecentric/keycloak)
- [ ] **0.2** 기존 Keycloak DB dump (60-postgres)
- [ ] **0.3** 기존 Realm/Client/User 설정 export (JSON)
- [ ] **0.4** DNS 레코드 설계
  - `keycloak.dev.unifiedmeta.net` → Public Ingress (OIDC 전용)
  - `keycloak-admin.dev.unifiedmeta.net` → Internal Ingress (Admin 전용)

### Phase 1: ArgoCD App 생성

- [ ] **1.1** `gitops-apps/bootstrap/keycloak.yaml` 생성
  ```yaml
  apiVersion: argoproj.io/v1alpha1
  kind: Application
  metadata:
    name: keycloak
  spec:
    source:
      chart: keycloak
      repoURL: https://charts.bitnami.com/bitnami
      targetRevision: "*"
      helm:
        values: |
          auth:
            adminUser: admin
          postgresql:
            enabled: false
          externalDatabase:
            host: postgres.dev.unifiedmeta.net
            database: keycloak
          proxyHeaders: xforwarded
          production: true
  ```
- [ ] **1.2** Ingress 설정 (Public OIDC)
  ```yaml
  ingress:
    enabled: true
    ingressClassName: nginx         # Public Ingress
    hostname: keycloak.dev.unifiedmeta.net
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
    tls: true
    path: /realms
    extraPaths:
      - path: /.well-known
  ```
- [ ] **1.3** Ingress 설정 (Internal Admin)
  ```yaml
  adminIngress:
    enabled: true
    ingressClassName: nginx-internal
    hostname: keycloak-admin.dev.unifiedmeta.net
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
    tls: true
  ```

### Phase 2: CiliumNetworkPolicy 적용

- [ ] **2.1** Public 트래픽 정책
  ```yaml
  apiVersion: cilium.io/v2
  kind: CiliumNetworkPolicy
  metadata:
    name: keycloak-public-oidc
    namespace: keycloak
  spec:
    endpointSelector:
      matchLabels:
        app.kubernetes.io/name: keycloak
    ingress:
      - fromEndpoints:
          - matchLabels:
              app.kubernetes.io/name: ingress-nginx  # Public
        toPorts:
          - ports:
              - port: "8080"
            rules:
              http:
                - method: GET
                  path: "/realms/.*"
                - method: POST
                  path: "/realms/.*/protocol/openid-connect/.*"
                - method: GET
                  path: "/.well-known/.*"
  ```
- [ ] **2.2** Admin 트래픽 정책 (Internal Ingress만 허용)
- [ ] **2.3** 외부 DB 접근 (60-postgres) Egress 정책

### Phase 3: 데이터 마이그레이션

- [ ] **3.1** K8s Pod → 기존 60-postgres DB 연결 확인
- [ ] **3.2** 기존 Realm 데이터 import
- [ ] **3.3** SSO 연동 서비스 동작 확인 (Grafana, ArgoCD, Rancher, Harbor, Teleport)

### Phase 4: 정리

- [ ] **4.1** 기존 `25-keycloak` Terraform 스택 정리
  - EC2 인스턴스 제거
  - Internal ALB 제거
  - DNS 레코드 → K8s Ingress로 전환
- [ ] **4.2** `gitops-apps/keycloak-ingress/` 디렉토리 제거 (EC2 프록시용)
- [ ] **4.3** `gitops-apps/bootstrap/keycloak-ingress.yaml` 제거
- [ ] **4.4** 문서 업데이트

## ⚠️ 선행 조건

- **Cilium CNI 전환 완료** (CiliumNetworkPolicy L7 사용을 위해 필수)
- `60-postgres` 스택 정상 동작 (Keycloak DB)
- Dual Ingress (Public + Internal) 셋업 완료

## 🔗 Dependencies

- `2026-02-08-cilium-cni-migration.md` — Cilium 전환 (선행 필수)
- `60-postgres` — 외부 DB
- `55-bootstrap` — ArgoCD App 등록
- `2026-02-07-keycloak-idp-adoption.md` — 기존 Keycloak 도입 계획

## 📎 References

- [17-cilium-cni-architecture.md §6](../architecture/17-cilium-cni-architecture.md) — Keycloak K8s 마이그레이션 상세
- [11-keycloak-idp-strategy.md](../architecture/11-keycloak-idp-strategy.md) — Keycloak IdP 전략
- [Bitnami Keycloak Helm Chart](https://github.com/bitnami/charts/tree/main/bitnami/keycloak)

## 🏷️ Labels

`keycloak`, `k8s-migration`, `cilium`, `phase-6`

## 📌 Priority

**High** — Cilium 재구축과 동시 진행

## 📅 예상 기간

Phase 6 (D14-16) 내 동시 진행
