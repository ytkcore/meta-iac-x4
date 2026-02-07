# [INFRA] Keycloak 통합 IdP 도입 — 플랫폼 SSO & OIDC 기반 인증 체계

## 📋 Summary

플랫폼 전체 서비스(Grafana, ArgoCD, Rancher, Harbor, Teleport)에 대한 통합 SSO와
K8s OIDC 기반 인증을 구현하기 위해 Keycloak을 중앙 IdP로 도입한다.
현재 각 서비스별로 분산된 인증 체계를 중앙화하고, AWS IAM OIDC와 연계하여 IRSA 기반
Pod-level 권한 관리의 기반도 마련한다.

## 🎯 Goals

1. **SSO**: 한 번 로그인으로 모든 플랫폼 서비스 접근
2. **중앙 사용자 관리**: 단일 지점에서 사용자/그룹/역할 관리
3. **OIDC 표준화**: K8s API, AWS IAM, 서비스 인증 모두 OIDC 기반
4. **멀티테넌트 준비**: Realm 기반 고객별 테넌트 분리 가능
5. **감사 통합**: 모든 인증 이벤트 중앙 로깅

## 📊 영향 범위

| 서비스 | 연동 방식 | 난이도 |
|--------|---------|-------|
| Grafana | Generic OAuth OIDC Client | 쉬움 |
| ArgoCD | argocd-cm OIDC 설정 | 쉬움 |
| Rancher | UI에서 Keycloak OIDC 선택 | 쉬움 |
| Harbor | Admin OIDC Auth Provider | 중간 |
| Teleport | tctl OIDC Connector | 중간 |
| K8s API | kube-apiserver --oidc-issuer-url | 중간 |
| AWS IAM | IAM OIDC Provider 등록 | 어려움 |

## 📋 Tasks

### Phase 0: Keycloak 배포

- [ ] **0.1** Keycloak EC2 배포 (Golden Image 기반, 25-keycloak 스택)
- [ ] **0.2** PostgreSQL DB 연결 (60-postgres 또는 전용)
- [ ] **0.3** Internal ALB 설정 (Harbor 패턴)
- [ ] **0.4** DNS 설정: `keycloak.unifiedmeta.net` (Private Zone)
- [ ] **0.5** TLS 설정 (ACM)
- [ ] **0.6** 초기 Realm/Client/User 구성

### Phase 1: SSO 연동 (서비스별)

- [ ] **1.1** Grafana OIDC 연동 (Pilot)
- [ ] **1.2** ArgoCD OIDC 연동
- [ ] **1.3** Rancher OIDC 연동
- [ ] **1.4** Harbor OIDC 연동
- [ ] **1.5** Teleport OIDC Connector 등록

### Phase 2: K8s & AWS 연동

- [ ] **2.1** K8s API Server OIDC 설정 (RKE2 config.yaml)
- [ ] **2.2** S3 OIDC Discovery Endpoint 구성 (IRSA 용)
- [ ] **2.3** AWS IAM OIDC Provider 등록
- [ ] **2.4** ALBC용 IRSA Role 생성
- [ ] **2.5** ALBC IP mode 전환

### Phase 3: 운영

- [ ] **3.1** 사용자/그룹 RBAC 매핑
- [ ] **3.2** 감사 로그 설정 (CloudWatch 연동)
- [ ] **3.3** Backup/Restore 절차 수립

## ⚠️ 선행 조건

- `60-postgres` 스택 완료 (Keycloak DB)
- Internal ALB 패턴 검증 완료 (Harbor에서 이미 검증)
- DNS Private Zone 구성 완료

## ⚠️ 주요 고려사항

1. **Keycloak은 K8s 외부에 배포** — 인증 대상에 인증 시스템이 의존하면 안 됨
2. **IRSA ≠ Keycloak** — Pod IRSA는 K8s ServiceAccount 토큰 사용, Keycloak과 별개
3. **단계적 도입** — Grafana부터 시작하여 점진적 확산
4. **HA** — Prod 환경에서는 Keycloak 이중화 필요

## 🔗 Dependencies

- `60-postgres`: DB
- `10-golden-image`: EC2 기반
- `15-access-control`: Teleport 연동
- `55-bootstrap`: ArgoCD, nginx-ingress 연동

## 📎 References

- [Keycloak 공식 문서](https://www.keycloak.org/documentation)
- [docs/architecture/keycloak-idp-strategy.md](../architecture/keycloak-idp-strategy.md)
- [docs/architecture/nlb-architecture.md](../architecture/nlb-architecture.md)
- [docs/jira/albc-adoption.md](albc-adoption.md) — ALBC Jira (선행)
