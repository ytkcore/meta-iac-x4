# 90-credential-init — 크리덴셜 부트스트랩 전략 수립

> **날짜**: 2026-02-13  
> **상태**: 📋 전략 확정 (구현 미착수)  
> **라벨**: `architecture`, `security`, `vault`, `sso`, `v0.6-planning`  
> **우선순위**: High

---

## 배경

배포 완료 후 관리자 크리덴셜 확보 → 서비스 초기화 → SSO 전환까지의 워크플로우에 글로벌 표준(Vault-First + ESO)을 적용하기 위한 전략 수립.

## 논의 과정에서 확인된 핵심 사실

| # | 발견 | 의미 |
|---|------|------|
| 1 | 대부분의 Secret은 **관리자 콘솔 비밀번호** | 서비스 기동에 불필요, 로그인 시만 필요 |
| 2 | 서비스 기동 필수 Secret은 Keycloak DB PW, ALBC AWS Creds 정도 | 전체 ESO 아닌 선별 적용 |
| 3 | SSO 전환 시 OIDC Client Secret 발생 → 지속 관리 필요 | ESO 필요성의 근거 |
| 4 | SSO 전환해도 로컬 id/pw 공존 (break-glass) | Keycloak 장애 시 로컬 admin 접근 |
| 5 | 전 서비스 SSO 기본 구성 → OIDC Secret 다수 → Vault + ESO 정당화 | "과잉" 아닌 "필수" |

## 확정 아키텍처

### 스택 배포 시퀀스

```
55-bootstrap:  Vault 서버 배포 (인프라 레디)
60~80:         모든 서비스 배포 (기본 id/pw로 기동)
90-credential: ESO 배포 → SSO 구성 → OIDC Secret Vault 관리 활성화
```

### SSO 대상

| 서비스 | OIDC 지원 | break-glass |
|--------|:--------:|:-----------:|
| ArgoCD | ✅ | `admin` 로컬 |
| Grafana | ✅ | `admin` 로컬 |
| Harbor | ✅ | `admin` 로컬 |
| Rancher | ✅ | `admin` 로컬 |
| Longhorn | ❌ | basic-auth / Pomerium |

### Day-1 관리자 시나리오 (10단계)

1. `terraform apply` (00~80)
2. `terraform output platform_credentials` → 초기 PW 확보
3. Vault Unseal 확인 (KMS 자동)
4. Keycloak 로그인 → Realm + 사용자 + OIDC Client 생성
5. `vault-seed.sh` → OIDC Secret Vault 저장
6. ESO + ExternalSecret 배포 (ArgoCD auto-sync)
7. 서비스 SSO 활성화 (Helm values)
8. SSO 로그인 검증
9. break-glass 검증 (Keycloak 중지 → 로컬 admin)
10. 초기 Secret 정리 + MFA 활성화

## 구현 범위 (5개 WP)

| WP | 내용 | 상태 |
|:--:|------|:----:|
| 1 | `terraform output platform_credentials` 추가 | ⬜ |
| 2 | ESO 배포 + ClusterSecretStore | ⬜ |
| 3 | OIDC Client Secret → Vault seed 스크립트 | ⬜ |
| 4 | 서비스별 SSO Helm values 설정 (4개) | ⬜ |
| 5 | Post-Deploy Guide + TODO 업데이트 | ⬜ |

## 참조

- [구현 계획 상세](../../.gemini/antigravity/brain/aea60a13-4caa-4755-bc27-eaad56ff0fd8/implementation_plan.md)
- [00-csp-independence-todo.md](../architecture/00-csp-independence-todo.md)
- [post-deployment-operations-guide.md](../guides/post-deployment-operations-guide.md)
