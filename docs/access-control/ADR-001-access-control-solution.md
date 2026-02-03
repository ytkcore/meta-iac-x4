# ADR-001: 접근제어 솔루션 선정

## 메타데이터

| 항목 | 내용 |
|:---|:---|
| **ID** | ADR-001 |
| **제목** | 접근제어 솔루션 선정 |
| **상태** | Accepted |
| **작성일** | 2026-02-03 |
| **작성자** | Platform Team |
| **검토자** | - |

---

## 1. 컨텍스트 (Context)

### 현재 상황
- ArgoCD, Rancher, Harbor 등 관리 도구가 **Public LoadBalancer**를 통해 인터넷에 노출
- 개발 환경 임시 조치로 `0.0.0.0/0` Ingress 허용 중
- 멀티클라우드(AWS, GCP, Azure) 및 온프레미스 환경 지원 필요
- 고객사 납품 시 **라이선스 비용 없이** 제공해야 함

### 요구사항
1. **보안**: Public 노출 제거, Zero Trust 아키텍처 구현
2. **범용성**: 멀티클라우드 + 온프레미스 + 폐쇄망 지원
3. **비용**: 오픈소스 또는 무료 티어 활용
4. **컴플라이언스**: ISMS-P 감사 대응 가능 (세션 녹화, 접근 로그)
5. **운영성**: K8s 네이티브, Helm Chart 배포 지원

---

## 2. 결정 (Decision)

### 통합 솔루션

| 구분 | 선정 솔루션 | 이유 |
|:---|:---|:---|
| **멀티클라우드 + 온프레미스** | **Teleport Community Edition** | 오픈소스, 세션 녹화, K8s 네이티브 |

### CSP별 보조 솔루션

| CSP | 솔루션 | 이유 |
|:---|:---|:---|
| **AWS** | SSM Session Manager | 무료, IAM 통합, SSH 포트 오픈 불필요 |
| **GCP** | Identity-Aware Proxy (IAP) | 무료, Google SSO 자동 통합 |
| **Azure** | Azure AD App Proxy | 무료 (Web 앱), Azure AD 통합 |

### 폐쇄망 솔루션

| 구분 | 선정 솔루션 | 이유 |
|:---|:---|:---|
| **폐쇄망 (Air-Gapped)** | **Apache Guacamole** | 오픈소스, 브라우저 기반, 외부 연결 불필요 |

---

## 3. 아키텍처 (Architecture)

```
┌─────────────────────────────────────────────────────────────────┐
│                         IdP (SSO)                                │
│              Google Workspace / Okta / Keycloak                  │
└─────────────────────────────────────────────────────────────────┘
                                │
        ┌───────────────────────┴───────────────────────┐
        ▼                                               ▼
┌───────────────────┐                       ┌───────────────────┐
│  Teleport Proxy   │                       │ CSP Native Tools  │
│  (통합 접근제어)   │                       │ (보조 접근)        │
├───────────────────┤                       ├───────────────────┤
│ • SSH Access      │                       │ • AWS SSM         │
│ • K8s Access      │                       │ • GCP IAP         │
│ • DB Access       │                       │ • Azure Bastion   │
│ • Web Apps        │                       │                   │
│ • Session Record  │                       │                   │
└─────────┬─────────┘                       └─────────┬─────────┘
          │                                           │
          └─────────────────┬─────────────────────────┘
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Target Infrastructure                       │
├────────────────┬────────────────┬────────────────┬──────────────┤
│     AWS VPC    │    GCP VPC     │   Azure VNet   │   On-Prem    │
│   K8s/RKE2     │      GKE       │      AKS       │   VMware     │
│   ArgoCD       │                │                │   Bare Metal │
│   Rancher      │                │                │              │
└────────────────┴────────────────┴────────────────┴──────────────┘
```

---

## 4. 대안 검토 (Alternatives Considered)

### 검토한 솔루션

| 솔루션 | 장점 | 단점 | 탈락 사유 |
|:---|:---|:---|:---|
| **AWS Client VPN** | AWS 네이티브, 안정적 | AWS 전용, 비용 발생 | 멀티클라우드 미지원 |
| **Cloudflare Access** | 글로벌 PoP, SSO 통합 | SaaS 의존, 규제 이슈 | 규제 민감 고객 대응 어려움 |
| **Tailscale** | 설치 간편, 무료 | 세션 녹화 없음 | ISMS-P 감사 대응 부족 |
| **HashiCorp Boundary** | Dynamic Secrets | 높은 러닝 커브 | 구축/운영 복잡도 |
| **국산 PAM (SecuID 등)** | CC 인증, ISMS-P 친화 | 고비용, K8s 미지원 | 라이선스 비용 부담 |

### 선정 근거

**Teleport 선정 이유:**
1. ✅ Apache 2.0 라이선스 (상업 사용 무료)
2. ✅ 멀티클라우드 + 온프레미스 + 폐쇄망 지원
3. ✅ SSH, K8s, DB, Web 모든 접근 통합
4. ✅ 세션 녹화 및 감사 로그 (ISMS-P 대응)
5. ✅ Helm Chart 표준 배포
6. ✅ 글로벌 레퍼런스 (Elastic, Snowflake, Nasdaq)
7. ✅ 국내 레퍼런스 (토스, 뱅크샐러드)

**Guacamole 선정 이유 (폐쇄망):**
1. ✅ Apache 2.0 라이선스 (완전 무료)
2. ✅ 인터넷 연결 불필요
3. ✅ 브라우저 기반 (클라이언트 설치 불필요)
4. ✅ SSH, RDP, VNC 프로토콜 지원
5. ✅ 공공/제조/금융 폐쇄망 레퍼런스 다수

---

## 5. 결과 (Consequences)

### 예상 효과

| 항목 | Before | After |
|:---|:---|:---|
| **Public 노출** | ArgoCD, Rancher, Harbor 인터넷 노출 | 완전 제거, 인증된 사용자만 접근 |
| **접근 감사** | 수동 로그 수집 | 자동 세션 녹화 + 감사 로그 |
| **비용** | Public LB 비용 발생 | 라이선스 비용 $0 |
| **SSO 통합** | 개별 인증 | 통합 SSO (Google/Okta) |
| **멀티클라우드** | AWS 전용 | AWS/GCP/Azure/OnPrem 통합 |

### 장점
- ✅ 비용 제로: 오픈소스 라이선스로 고객사 부담 없음
- ✅ 보안 강화: Zero Trust 아키텍처 구현
- ✅ 컴플라이언스: ISMS-P 감사 증적 자동화
- ✅ 확장성: 신규 CSP/온프레미스 추가 용이

### 단점
- ⚠️ 운영 부담: Teleport 클러스터 자체 운영 필요
- ⚠️ 한글 문서: 공식 문서가 영어, 내부 가이드 작성 필요
- ⚠️ 기능 제한: Enterprise 기능(RBAC 상세 등) 일부 제한

### 리스크 및 완화 방안

| 리스크 | 확률 | 영향 | 완화 방안 |
|:---|:---:|:---:|:---|
| Teleport 장애 시 접근 불가 | 중 | 상 | HA 구성, CSP 네이티브 툴 백업 |
| 버전 업그레이드 호환성 | 중 | 중 | 스테이징 환경 사전 테스트 |
| 국내 규제 변경 | 하 | 중 | 국산 PAM 병행 옵션 보유 |

---

## 6. 구현 계획 (Implementation)

### Phase 1: 즉시 (1일)
- [ ] Teleport Helm Chart 배포
- [ ] Public LB 제거, Service를 ClusterIP로 변경
- [ ] SSO 연동 (Google Workspace)

### Phase 2: 단기 (1주)
- [ ] K8s 접근 정책 구성 (Role 정의)
- [ ] 세션 녹화 스토리지 구성
- [ ] 운영 가이드 문서 작성

### Phase 3: 중기 (1개월)
- [ ] DB 접근 통합 (PostgreSQL, Neo4j)
- [ ] Just-in-Time 승인 워크플로우 구성
- [ ] ISMS-P 감사 증적 템플릿 작성

### Phase 4: 고객 납품 준비
- [ ] 표준 배포 Helm Values 작성
- [ ] 폐쇄망용 Guacamole 패키지 준비
- [ ] 납품 문서 (설계서, 운영 가이드)

---

## 7. 관련 문서

| 문서 | 경로 |
|:---|:---|
| 글로벌 솔루션 비교 | [01-global-solutions.md](research/01-global-solutions.md) |
| 국내 트렌드 분석 | [02-korea-trends.md](research/02-korea-trends.md) |
| 고객사 납품 권장안 | [03-customer-delivery.md](research/03-customer-delivery.md) |
| 보안 스캔 보고서 | [../security-scan-report.md](../security-scan-report.md) |

---

## 8. 변경 이력

| 버전 | 날짜 | 변경 내용 | 작성자 |
|:---|:---|:---|:---|
| 1.0 | 2026-02-03 | 초안 작성 | Platform Team |
