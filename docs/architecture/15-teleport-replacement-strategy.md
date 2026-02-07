# Teleport 대체 전략 — 고객 납품용 접근 제어 솔루션

**작성일**: 2026-02-07  
**상태**: 전략 수립 단계  
**관련**: [13-access-gateway-architecture.md](13-access-gateway-architecture.md), [Apache Guacamole 리서치](../research/apache_guacamole_adoption_review.md)

---

## 1. 문제 정의

### Teleport의 납품 부적합 사유

| 문제 | 상세 | 영향도 |
|------|------|--------|
| **라이선스** | AGPLv3 — 수정 시 전체 소스 공개 의무 | 🔴 치명적 |
| **재판매 비용** | Teleport Enterprise 없이 상용 패키징 불가, Enterprise는 사용자 수 기반 과금 | 🔴 치명적 |
| **브랜딩** | White-label / OEM 불가 (AGPLv3 제약) | 🟡 중요 |
| **Windows RDP** | Community Edition은 데스크톱 접근 미지원, Enterprise 기능 | 🟡 중요 |
| **고객사 종속** | 고객도 AGPLv3 의무 승계 → 법적 부담 | 🟡 중요 |

### 핵심 질문

> **Teleport가 수행하는 역할(L4: Access Proxy + 감사)을 고객 납품 시에는 어떤 솔루션으로 대체할 것인가?**

---

## 2. Teleport의 역할 분해

Teleport를 단일 블록으로 보지 않고, **수행하는 기능 단위로 분해**하면 대체 전략이 명확해집니다.

```
Teleport의 역할:
  ┌─────────────────────────────────────────────────┐
  │  F1. SSH 접속 (서버 원격 관리)                    │  → Guacamole SSH
  │  F2. Web App 프록시 (내부 서비스 접근)             │  → nginx + OAuth2 Proxy
  │  F3. K8s API 접근 (kubectl 인증)                  │  → Keycloak OIDC
  │  F4. DB 접근 (PostgreSQL, MySQL 프록시)            │  → Guacamole + pgAdmin
  │  F5. 세션 녹화 / 감사 로그                         │  → Guacamole 내장
  │  F6. RBAC (역할 기반 접근 제어)                    │  → Keycloak + OPA
  │  F7. MFA                                          │  → Keycloak + TOTP
  └─────────────────────────────────────────────────┘
```

> **핵심 인사이트**: Teleport의 기능은 **이미 다른 오픈소스 솔루션의 조합으로 100% 대체 가능**합니다.

---

## 3. 대체 전략: 3가지 옵션

### Option A: Apache Guacamole 중심 (★ 추천)

```
                    ┌───────────────────────┐
                    │    Keycloak (SSO)      │  ← 사용자 인증 총괄
                    │    + TOTP (MFA)        │
                    └─────────┬─────────────┘
                              │ OIDC
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
     ┌────────────┐  ┌────────────────┐  ┌─────────────────┐
     │ Guacamole  │  │ OAuth2 Proxy   │  │ K8s OIDC Auth   │
     │            │  │ + nginx        │  │ (kubectl SSO)   │
     │ • SSH      │  │                │  │                 │
     │ • RDP ★    │  │ • Web App      │  │ • K8s API       │
     │ • VNC      │  │   프록시       │  │   접근           │
     │ • 세션녹화 │  │ • 내부 서비스  │  │                 │
     └────────────┘  └────────────────┘  └─────────────────┘
```

| Teleport 기능 | 대체 솔루션 | 라이선스 | 성숙도 |
|:---|:---|:---|:---|
| F1. SSH 접속 | **Guacamole** | Apache 2.0 ✅ | ★★★★★ |
| F2. Web App 프록시 | **OAuth2 Proxy + nginx** | Apache 2.0 ✅ | ★★★★★ |
| F3. K8s API | **Keycloak OIDC + kubectl** | Apache 2.0 ✅ | ★★★★☆ |
| F4. DB 접근 | **Guacamole (SSH tunnel)** | Apache 2.0 ✅ | ★★★☆☆ |
| F5. 세션 녹화 | **Guacamole** 내장 | Apache 2.0 ✅ | ★★★★★ |
| F6. RBAC | **Keycloak** 그룹/역할 | Apache 2.0 ✅ | ★★★★★ |
| F7. MFA | **Keycloak** TOTP/WebAuthn | Apache 2.0 ✅ | ★★★★★ |

**장점**:
- 전체 스택 **Apache 2.0** → 소스 공개 의무 없음, 상용 납품 안전
- **Windows RDP 네이티브 지원** (Teleport Enterprise 없이 불가능했던 기능)
- Docker Compose 단일 패키지로 **어플라이언스형 납품** 가능
- White-label/브랜딩 자유 (Extension 시스템)
- ISMS-P 세션 녹화 요건 충족

**단점**:
- K8s 네이티브 접근은 Teleport 대비 약함 (SSH 경유)
- 여러 컴포넌트 조합 → 통합 관리 UI 필요

---

### Option B: HashiCorp Boundary

```
Boundary = Teleport + Vault 인증 통합
```

| 항목 | 상세 |
|------|------|
| 라이선스 | **BSL 1.1** (소스 공개, 경쟁 제품에 사용 금지) |
| SSH | ✅ 지원 |
| K8s | ✅ 지원 |
| DB | ✅ 네이티브 지원 (Vault 자동 크리덴셜) |
| 세션 녹화 | ❌ 미지원 |
| Windows RDP | ❌ 미지원 |
| Vault 연동 | ✅ 네이티브 (동일 HashiCorp 생태계) |

**판정**: ❌ **부적합**
- BSL 라이선스 → 재판매/패키징 가능하나 경쟁 솔루션에 사용 불가
- 세션 녹화 없음 → **ISMS-P 부적합**
- Windows RDP 없음 → 고객 환경에서 치명적 제약

---

### Option C: 하이브리드 (Teleport 사내 + Guacamole 납품)

이미 `80-access-gateway` 스택에 `access_solution` 변수가 설계되어 있으므로,
**환경별로 다른 솔루션을 선택**하는 패턴.

```hcl
# 사내 환경
variable "access_solution" {
  default = "teleport"  # 내부팀은 Teleport 사용 (K8s, SSH, App 강력)
}

# 고객 납품 환경
variable "access_solution" {
  default = "guacamole"  # Apache 2.0, 라이선스 안전
}
```

**장점**:
- 사내: Teleport의 강력한 K8s/SSH 기능 유지
- 납품: 라이선스 안전한 Guacamole 사용
- 기존 아키텍처(`80-access-gateway`) 그대로 활용

**단점**:
- 2개 솔루션 동시 유지 보수 필요 (학습/운영 비용)
- 납품 모듈과 사내 모듈의 기능 격차 관리 필요

---

## 4. 추천 전략: Option C (하이브리드) → 점진적 Option A 수렴

### Phase 1: 현재 유지 + 납품 모듈 추가 (2~3일)

```
80-access-gateway/
  └── modules/access-gateway/
        ├── teleport/      ← 기존 (사내용)
        └── guacamole/     ← 신규 (납품용)
```

| 작업 | 산출물 |
|------|--------|
| Guacamole Docker Compose 템플릿 작성 | 납품 패키지 기본 구조 |
| Keycloak OIDC ↔ Guacamole 연동 | SSO 통합 |
| 세션 녹화 + 스토리지 설정 | ISMS-P 충족 |
| White-label Extension 기본 구성 | 브랜딩 준비 |

### Phase 2: Web App 프록시 계층 구축 (2~3일)

Teleport의 App Access 역할 대체:

| 기능 | 솔루션 | 구현 |
|------|--------|------|
| 내부 서비스 인증 프록시 | **OAuth2 Proxy** | nginx + OAuth2 Proxy sidecar |
| 인증서 자동화 | **cert-manager** | 이미 구축 완료 ✅ |
| DNS 자동화 | **external-dns** | 이미 구축 완료 ✅ |

```
기존 (Teleport):
  harbor.teleport.unifiedmeta.net → harbor.unifiedmeta.net

대체 (OAuth2 Proxy):
  harbor.unifiedmeta.net → OAuth2 Proxy → harbor (내부)
  (Keycloak OIDC 인증 후 접근 허용)
```

### Phase 3: 납품 패키지 완성 (3~5일)

| 항목 | 납품 패키지 구성 |
|------|-----------------|
| **접근 게이트웨이** | Guacamole (SSH/RDP/VNC) |
| **SSO/MFA** | Keycloak (OIDC + TOTP) |
| **시크릿** | Vault (동적 시크릿, 선택적) |
| **인증서** | cert-manager (Let's Encrypt) |
| **배포 형태** | Docker Compose 또는 Helm Chart |
| **브랜딩** | 고객사 로고/CSS 교체 |

---

## 5. 납품 아키텍처 스택 비교 (최종)

```
                사내 환경                          고객 납품 환경
        ┌─────────────────────┐           ┌─────────────────────┐
  L4    │ Teleport (Access)   │     L4    │ Guacamole (Access)  │
        │ SSH, K8s, App, DB   │           │ SSH, RDP, VNC       │
        │ AGPLv3              │           │ Apache 2.0 ✅       │
        ├─────────────────────┤           ├─────────────────────┤
  L3    │ Vault (Secrets)     │     L3    │ Vault (Secrets)     │
        │ BSL 1.1             │           │ BSL 1.1 (자체호스팅 OK) │
        ├─────────────────────┤           ├─────────────────────┤
  L2    │ SPIRE (Workload ID) │     L2    │ (선택적)             │
        │ Apache 2.0          │           │ Apache 2.0          │
        ├─────────────────────┤           ├─────────────────────┤
  L1    │ Keycloak (Human ID) │     L1    │ Keycloak (Human ID) │
        │ Apache 2.0          │           │ Apache 2.0          │
        └─────────────────────┘           └─────────────────────┘
            access_solution                 access_solution
              = "teleport"                    = "guacamole"
```

> **핵심**: L1(Keycloak), L2(SPIRE), L3(Vault)는 **사내/납품 동일**. L4만 교체.

---

## 6. 기존 아키텍처와의 정합성

### 이미 준비된 추상화 레이어

기존 `80-access-gateway` 스택의 설계가 **이미 솔루션 교체를 전제**로 되어 있어서,
추가 아키텍처 변경 없이 모듈만 추가하면 됩니다.

| 기존 설계 요소 | 활용 방식 |
|:---|:---|
| `access_solution` 변수 | `"guacamole"` 값 추가 |
| `service_endpoint` 표준 output | Guacamole Connection Profile로 변환 |
| `modules/access-gateway/` 디렉토리 | `guacamole/` 모듈 추가 |

### 코드 변경 범위

```
변경 필요:
  modules/access-gateway/guacamole/     ← 신규 모듈 (핵심)
  stacks/dev/80-access-gateway/main.tf  ← guacamole 모듈 호출 추가

변경 불필요:
  서비스 스택들 (40-harbor, 55-bootstrap, ...)  ← service_endpoint 유지
  15-access-control                              ← Teleport 그대로
  기타 모든 스택                                  ← 무변경
```

---

## 7. 리스크 분석

| 리스크 | 영향 | 대응 |
|--------|------|------|
| Guacamole K8s 접근 간접적 | 중간 | Bastion SSH 경유 + kubectl exec alias |
| 2개 솔루션 유지 보수 비용 | 중간 | 80-access-gateway 추상화로 분리 |
| Guacamole 스케일 한계 | 낮음 | 납품 환경 = 소~중 규모 (충분) |
| OAuth2 Proxy 관리 복잡도 | 낮음 | Helm Chart로 표준화 |
| Vault BSL 라이선스 우려 | 낮음 | 자체 호스팅은 허용, 경쟁 SaaS만 제한 |

---

## 8. 결론

| 결정 사항 | 내용 |
|:---|:---|
| **사내 환경** | Teleport 유지 (L4, K8s/SSH/App 강력) |
| **고객 납품** | **Apache Guacamole + OAuth2 Proxy** (Apache 2.0, ISMS-P 충족) |
| **전환 방식** | `80-access-gateway` 스택의 `access_solution` 변수 교체 |
| **추가 개발** | `modules/access-gateway/guacamole/` 모듈 1개 |
| **소요 시간** | 약 **1~2주** (Phase 1~3) |
| **아키텍처 변경** | **없음** (기존 설계가 이미 교체를 전제) |

> **"Teleport를 무엇으로 대체하는가"의 답은 이미 아키텍처 안에 있었습니다.**  
> `access_solution = "guacamole"` — 변수 하나만 바꾸면 됩니다.
