# 고객사 납품용 접근제어 솔루션 권장안

> 인프라 구축 + 솔루션 납품 시 최적의 접근제어 전략

---

## 1. 선정 기준

| 기준 | 요구사항 |
|:---|:---|
| **라이선스** | 오픈소스 또는 무료 (고객사 비용 부담 없음) |
| **Self-Hosted** | 고객사 환경에 직접 배포 가능 |
| **레퍼런스** | 글로벌 + 국내 도입 사례 풍부 |
| **커버리지** | 멀티클라우드 + 온프레미스 + 폐쇄망 |
| **K8s 네이티브** | Helm Chart 제공, 컨테이너 배포 |

---

## 2. 통합 솔루션: Teleport Community Edition

### 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                     Teleport (Self-Hosted)                       │
│              오픈소스 | Apache 2.0 License | 무료               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐           │
│   │   SSH   │  │  K8s    │  │Database │  │  Web    │           │
│   │  Access │  │  Access │  │  Access │  │  Apps   │           │
│   └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘           │
│        │            │            │            │                  │
│        └────────────┴────────────┴────────────┘                  │
│                          │                                       │
│                   [세션 녹화 + 감사 로그]                         │
│                   [RBAC + SSO 통합]                              │
│                   [Certificate-Based Auth]                       │
│                                                                  │
├────────────────┬─────────────────┬─────────────────┬────────────┤
│      AWS       │       GCP       │      Azure      │  On-Prem   │
│   Teleport     │   Teleport      │   Teleport      │  Teleport  │
│    Agent       │    Agent        │    Agent        │   Agent    │
└────────────────┴─────────────────┴─────────────────┴────────────┘
```

### 상세 스펙

| 항목 | 상세 |
|:---|:---|
| **라이선스** | Apache 2.0 (상업 사용 무료) |
| **Self-Hosted** | ✅ Helm Chart, Docker, Binary 모두 제공 |
| **글로벌 레퍼런스** | Elastic, Snowflake, Nasdaq, DoorDash |
| **국내 레퍼런스** | 토스, 뱅크샐러드, 스타트업 다수 |
| **K8s 네이티브** | ✅ kubectl 접근, Pod exec 세션 녹화 |
| **세션 녹화** | ✅ SSH, K8s, DB 모든 세션 녹화 |
| **ISMS-P 대응** | ✅ 한글 보고서는 직접 작성 필요 |
| **폐쇄망 지원** | ✅ Air-gapped 설치 지원 |

### 배포 예시

```yaml
# Helm 배포
helm repo add teleport https://charts.releases.teleport.dev
helm install teleport-cluster teleport/teleport-cluster \
  --namespace teleport \
  --set clusterName=customer-cluster \
  --set proxyListenerMode=multiplex
```

---

## 3. CSP별 네이티브 솔루션 (비용 무료)

### AWS: SSM Session Manager

| 항목 | 상세 |
|:---|:---|
| **비용** | 완전 무료 (SSM 기본 기능) |
| **특징** | SSH 포트 오픈 불필요, IAM 기반 인증 |
| **제약** | AWS 전용, K8s 직접 지원 없음 |

```bash
# 접속 예시
aws ssm start-session --target i-0123456789abcdef0
```

---

### GCP: Identity-Aware Proxy (IAP)

| 항목 | 상세 |
|:---|:---|
| **비용** | 무료 (GCP 프로젝트 내) |
| **특징** | 브라우저 기반, Google SSO 자동 통합 |
| **제약** | GCP 전용, TCP 포워딩 가능 |

```bash
# SSH 접속 예시
gcloud compute ssh instance-name --tunnel-through-iap
```

---

### Azure: Azure AD App Proxy / Bastion Basic

| 항목 | 상세 |
|:---|:---|
| **비용** | App Proxy: 무료 / Bastion Basic: ~$0.19/시간 |
| **특징** | 브라우저 기반 RDP/SSH, VNet 통합 |
| **제약** | Azure 전용 |

---

## 4. 폐쇄망(Air-Gapped) 전용: Apache Guacamole

### 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                   폐쇄망 (Internet 완전 차단)                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   [운영자 PC] ──── [내부망] ──── [Guacamole Server]             │
│       │                              │                          │
│       │                              ▼                          │
│       │                     ┌────────────────┐                  │
│       │                     │   Target VMs   │                  │
│       │                     │  - SSH Linux   │                  │
│       │                     │  - RDP Windows │                  │
│       │                     │  - VNC         │                  │
│       │                     └────────────────┘                  │
│       │                              │                          │
│       └──── [브라우저 접속] ─────────┘                          │
│             HTML5 기반 (클라이언트 설치 불필요)                  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 상세 스펙

| 항목 | 상세 |
|:---|:---|
| **라이선스** | Apache 2.0 (완전 무료) |
| **클라이언트** | 웹 브라우저만 (HTML5) |
| **프로토콜** | SSH, RDP, VNC, Telnet 지원 |
| **폐쇄망 적합** | 외부 연결 불필요, 완전 Self-Hosted |
| **레퍼런스** | 공공기관, 제조업, 금융권 폐쇄망 |
| **국내 도입** | 삼성, LG, 현대 계열사 일부 |

### 배포 예시

```yaml
# Docker Compose
version: '3'
services:
  guacamole:
    image: guacamole/guacamole
    ports:
      - "8080:8080"
    environment:
      GUACD_HOSTNAME: guacd
      POSTGRES_HOSTNAME: postgres
  guacd:
    image: guacamole/guacd
  postgres:
    image: postgres:15
```

---

## 5. 최종 비교 매트릭스

| 구분 | 솔루션 | 비용 | 커버리지 | 세션녹화 | K8s지원 | 폐쇄망 |
|:---|:---|:---:|:---|:---:|:---:|:---:|
| **통합** | Teleport CE | 무료 | AWS/GCP/Azure/OnPrem | ✅ | ✅ | ✅ |
| **AWS** | SSM Session Manager | 무료 | AWS Only | ✅ | ❌ | ❌ |
| **GCP** | IAP | 무료 | GCP Only | ❌ | ❌ | ❌ |
| **Azure** | Azure AD App Proxy | 무료 | Azure Only (Web) | ❌ | ❌ | ❌ |
| **폐쇄망** | Guacamole | 무료 | Any (Self-Hosted) | 🔶 | ❌ | ✅ |

---

## 6. 표준 납품 패키지

```
┌─────────────────────────────────────────────────────────────────┐
│                    고객사 납품 표준 패키지                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  [Base Layer] ────────────────────────────────────────────────  │
│  │                                                               │
│  │   Teleport Community Edition (Helm 배포)                     │
│  │   - 모든 환경 통합 접근제어                                   │
│  │   - 세션 녹화 + 감사 로그                                     │
│  │   - SSO 통합 (SAML/OIDC)                                     │
│  │                                                               │
│  └─────────────────────────────────────────────────────────────  │
│                                                                  │
│  [CSP-Specific Layer] ─────────────────────────────────────────  │
│  │                                                               │
│  │   AWS → SSM Session Manager (EC2 직접 접속)                  │
│  │   GCP → IAP Tunnel (GCE 직접 접속)                           │
│  │   Azure → Azure Bastion Basic                                │
│  │                                                               │
│  └─────────────────────────────────────────────────────────────  │
│                                                                  │
│  [Air-Gap Layer] ──────────────────────────────────────────────  │
│  │                                                               │
│  │   Teleport (폐쇄망 설치) 또는 Guacamole                       │
│  │   - 인터넷 연결 없이 운영 가능                                │
│  │   - 브라우저 기반 접속                                        │
│  │                                                               │
│  └─────────────────────────────────────────────────────────────  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 7. 비용 요약 (고객사 부담 제로)

| 솔루션 | 라이선스 | 운영 비용 | 비고 |
|:---|:---|:---|:---|
| Teleport CE | Apache 2.0 | VM/K8s 리소스만 | 기능 제한 없음 |
| SSM Session Manager | AWS 내장 | 무료 | CloudWatch 로그 비용만 |
| GCP IAP | GCP 내장 | 무료 | |
| Guacamole | Apache 2.0 | VM 리소스만 | |

**고객사 추가 비용: $0** (인프라 리소스 비용만 발생)

---

## 8. 납품 문서 구성 (제안서용)

```
1. 접근제어 아키텍처 설계서
   ├── 1.1 통합 접근제어 (Teleport)
   ├── 1.2 CSP별 네이티브 연동 (SSM/IAP/Bastion)
   └── 1.3 폐쇄망 대응 (Guacamole)

2. 보안 컴플라이언스 매핑
   ├── 2.1 ISMS-P 2.5 접근통제 충족 항목
   ├── 2.2 세션 녹화 및 감사 로그 정책
   └── 2.3 최소 권한 원칙 적용 방안

3. 운영 가이드
   ├── 3.1 Teleport Helm 배포 절차
   ├── 3.2 사용자/역할 관리 절차
   └── 3.3 장애 대응 절차
```

---

## 참고 자료

- [Teleport Community Edition](https://goteleport.com/docs/deploy-a-cluster/open-source/)
- [Apache Guacamole](https://guacamole.apache.org/)
- [AWS SSM Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [GCP IAP](https://cloud.google.com/iap/docs)
