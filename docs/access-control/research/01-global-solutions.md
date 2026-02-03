# 글로벌 접근제어 솔루션 비교

> 멀티클라우드 + 온프레미스 환경에서의 글로벌 베스트 프랙티스

---

## 1. Zero Trust 아키텍처 개요

### 핵심 원칙

| 원칙 | 설명 |
|:---|:---|
| **Never Trust, Always Verify** | 네트워크 위치가 아닌 Identity 기반 인증 |
| **Least Privilege** | 최소 권한만 부여 |
| **Assume Breach** | 이미 침해되었다고 가정하고 설계 |
| **Verify Explicitly** | 모든 접근에 대해 명시적 검증 |

### Reference Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Identity Provider (IdP)                            │
│                     (Okta / Azure AD / Keycloak)                            │
│                              ↓ SAML/OIDC                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌───────────────┐    ┌───────────────┐    ┌───────────────┐              │
│   │ Cloudflare    │    │  Tailscale    │    │  Teleport     │              │
│   │ Access/Tunnel │    │  (Mesh VPN)   │    │  (Infra PAM)  │              │
│   └───────┬───────┘    └───────┬───────┘    └───────┬───────┘              │
│           │                    │                    │                       │
│           ▼                    ▼                    ▼                       │
│   ┌───────────────────────────────────────────────────────────────┐        │
│   │                    Control Plane (통합 정책 관리)              │        │
│   │         HashiCorp Boundary / Cloudflare Gateway               │        │
│   └───────────────────────────────────────────────────────────────┘        │
│                                                                              │
├────────────────┬────────────────┬────────────────┬───────────────────────────┤
│     AWS VPC    │    GCP VPC     │   Azure VNet   │      On-Premise DC        │
└────────────────┴────────────────┴────────────────┴───────────────────────────┘
```

---

## 2. Tier 1: 글로벌 엔터프라이즈 표준

### 2.1 Cloudflare Zero Trust (SASE)

| 구성 요소 | 역할 |
|:---|:---|
| **Cloudflare Access** | 모든 앱 앞단에서 SSO 인증 강제 |
| **Cloudflare Tunnel** | Inbound 포트 없이 내부 서비스 노출 |
| **Cloudflare Gateway** | DNS/HTTP 기반 정책 |
| **WARP Client** | Device Posture 검증 |

**장점:**
- 클라우드 불가지론: AWS, GCP, Azure, 온프레미스 모두 동일 방식
- 글로벌 PoP: 전 세계 300+ 데이터센터
- Zero Inbound: 방화벽 규칙 최소화

**채택 기업:** Shopify, Discord, Canva, DoorDash

---

### 2.2 Tailscale (WireGuard Mesh)

| 특징 | 설명 |
|:---|:---|
| **Mesh Topology** | 모든 노드가 P2P로 연결 |
| **NAT Traversal** | 복잡한 NAT 뒤에서도 자동 연결 |
| **SSO 통합** | Google, Okta, Azure AD 지원 |
| **ACL 정책** | Git 기반 정책 관리 |

**장점:**
- 온프레미스 친화적
- Subnet Router로 VPC 전체 노출 가능
- Exit Node로 IP 고정 가능

**채택 기업:** Vercel, HashiCorp, 1Password

---

### 2.3 Teleport (Infrastructure Access Platform)

| 특징 | 설명 |
|:---|:---|
| **SSH/K8s/DB 통합** | 단일 플랫폼에서 모든 인프라 접근 관리 |
| **Session Recording** | 모든 세션 녹화 및 재생 |
| **RBAC** | Role 기반 세분화된 권한 |
| **Audit Log** | SOC2, HIPAA 컴플라이언스 대응 |

**장점:**
- 오픈소스 (Self-hosted 가능)
- Certificate-Based Auth
- Just-in-Time Access

**채택 기업:** Elastic, Snowflake, Nasdaq

---

## 3. Tier 2: HashiCorp Stack

### HashiCorp Boundary + Vault

```
[개발자] → [Boundary Proxy] → [Target: K8s/DB/SSH]
              │
              ↓
         [Vault에서 동적 자격증명 발급]
```

**장점:**
- Terraform 생태계 통합
- Dynamic Secrets: 요청 시 생성, 사용 후 폐기
- Session Brokering: 실제 자격증명 노출 없이 접근

---

## 4. 솔루션 비교 매트릭스

| 기준 | Cloudflare | Tailscale | Teleport | Boundary |
|:---|:---:|:---:|:---:|:---:|
| **멀티클라우드** | ★★★★★ | ★★★★★ | ★★★★★ | ★★★★★ |
| **온프레미스** | ★★★★☆ | ★★★★★ | ★★★★★ | ★★★★★ |
| **구현 난이도** | ★★☆☆☆ | ★☆☆☆☆ | ★★★☆☆ | ★★★★☆ |
| **SSO 통합** | ★★★★★ | ★★★★☆ | ★★★★★ | ★★★★★ |
| **Audit/Compliance** | ★★★★★ | ★★★☆☆ | ★★★★★ | ★★★★★ |
| **비용 (소규모)** | 무료 | 무료 | 무료 | 무료 |
| **비용 (대규모)** | 중간 | 저가 | 고가 | 고가 |
| **브라우저 접근** | ★★★★★ | ★★☆☆☆ | ★★★★☆ | ★★★☆☆ |
| **CLI/터미널 접근** | ★★☆☆☆ | ★★★★★ | ★★★★★ | ★★★★★ |

---

## 5. 비용 비교 (월 기준, 50명)

| 방식 | 월 비용 | 비고 |
|:---|:---:|:---|
| Tailscale Team | $250 | $5/인 |
| Cloudflare Access Free | $0 | 50명까지 무료 |
| Teleport Cloud | $750 | $15/인 |
| AWS Client VPN | ~$500 | Endpoint + 연결 시간 |

---

## 6. 권장 조합

### 접근 유형별 솔루션

| 접근 유형 | 권장 솔루션 | 이유 |
|:---|:---|:---|
| **Web UI** | Cloudflare Tunnel | 브라우저 접속, SSO, Audit Log |
| **CLI/터미널** | Tailscale | 낮은 레이턴시, kubectl 직접 사용 |
| **고감도 인프라** | Teleport | 세션 녹화, Just-in-Time 승인 |

---

## 참고 자료

- [Cloudflare Zero Trust](https://www.cloudflare.com/zero-trust/)
- [Tailscale Documentation](https://tailscale.com/kb/)
- [Teleport Documentation](https://goteleport.com/docs/)
- [HashiCorp Boundary](https://www.boundaryproject.io/)
