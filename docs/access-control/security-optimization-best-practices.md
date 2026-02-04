# 보안 최적화 및 운영 Best Practices

> Teleport, SSH, RKE2 통합 환경의 글로벌 표준 보안 운영 가이드

---

## 1. SSH 포트 전략 (Port 22 vs Custom Port)

### 1.1 Port 22 변경 논쟁

| 전략 | 장점 | 단점 | 글로벌 채택률 |
|:---|:---|:---|:---|
| **Port 22 유지** | 표준 준수, 관리 단순 | 자동 스캔 대상 | ✅ **90%+** (Enterprise) |
| **비표준 포트** | 봇 스캔 회피 | 운영 복잡도 증가 | ⚠️ 10% (중소기업) |

### 1.2 글로벌 표준 권장사항

**실무 권장: Port 변경 + SG 차단 + Teleport (다층 방어)**

```
┌─────────────────────────────────────────────────────────────┐
│  Defense in Depth (계층적 방어)                              │
├─────────────────────────────────────────────────────────────┤
│  Layer 0: Port Obfuscation (선택적 추가 방어)                │
│           └─ SSH Port: 22 → 22022 (자동 봇 스캔 회피)       │
│                                                              │
│  Layer 1: Network (Security Group)                          │
│           └─ SSH (22022) Inbound: DENY ALL (0.0.0.0/0)      │
│                                                              │
│  Layer 2: Identity (Teleport)                               │
│           └─ SSO + MFA + Short-lived Certificates           │
│                                                              │
│  Layer 3: Audit (Logging)                                   │
│           └─ CloudTrail + Teleport Session Recording        │
│                                                              │
│  Layer 4: Break Glass (Emergency Access)                    │
│           └─ AWS SSM / Serial Console                       │
└─────────────────────────────────────────────────────────────┘
```

### 1.3 SSH Port 변경 실무 가이드

**Port 22 vs 비표준 포트 (22022, 2222 등)**

| 시나리오 | 권장 전략 | 이유 |
|:---|:---|:---|
| **엔터프라이즈** | Port 22 유지 | 툴체인 호환성, 감사 표준화 |
| **스타트업/중소** | **Port 변경 권장** | 봇 공격 로그 감소, 추가 방어층 |
| **멀티클라우드** | Port 변경 + Teleport | CSP별 Break Glass 대응 |
| **폐쇄망** | Port 22 유지 | 외부 위협 없음 |

**실전 포트 변경 방법:**

```bash
# /etc/ssh/sshd_config
Port 22022  # 22번 대신 22022 사용 (기억하기 쉬움)

# Security Group
Inbound Rules:
  - Port 22022: DENY 0.0.0.0/0 (기본)
  - Port 22022: ALLOW <관리용 IP> (Break Glass용, 평시 비활성)
```

> **Why Port Change Works in Practice?**  
> 1. ✅ 자동화된 봇 스캔 90% 이상 차단 (실제 로그 감소 확인)  
> 2. ✅ `/var/log/auth.log` 노이즈 제거 → 진짜 공격 탐지 용이  
> 3. ✅ SG 차단과 병행 시 "이중 잠금" 효과  
> 4. ⚠️ 진짜 공격자(포트 스캔)는 찾아낼 수 있으므로 "추가" 방어층일 뿐

**결론: SG 차단은 필수, 포트 변경은 선택이지만 실무에서 강력 권장**

---

## 2. Teleport Access Pattern (현재 프로젝트)

### 2.1 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                    Access Control Layers                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  [개발자 PC]                                                 │
│     │                                                        │
│     │ tsh login (SSO + MFA)                                  │
│     ▼                                                        │
│  ┌──────────────────────┐                                   │
│  │ Teleport Proxy/Auth  │  (15-teleport)                    │
│  │ - Public ALB (443)   │                                   │
│  │ - EC2 (t3.small×2)   │                                   │
│  └──────────┬───────────┘                                   │
│             │                                                │
│    ┌────────┼────────┐                                      │
│    ▼        ▼        ▼                                      │
│  ┌────┐  ┌────┐  ┌────┐                                    │
│  │SSH │  │K8s │  │DB  │                                    │
│  │Agnt│  │Agnt│  │Agnt│                                    │
│  └────┘  └────┘  └────┘                                    │
│   EC2     Pod     EC2                                       │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Agent 배치 전략

| 대상 | Agent 유형 | 배치 위치 | 우선순위 |
|:---|:---|:---|:---|
| **RKE2 Cluster** | Kube Agent | K8s Pod | ✅ **필수** |
| **DB 서버** | SSH Agent | Golden Image | ⚠️ 선택 (멀티클라우드 대비) |
| **RKE2 노드** | SSH Agent | Golden Image | ❌ 불필요 (kubectl로 충분) |

### 2.3 포트 매핑

| 서비스 | 포트 | 프로토콜 | Inbound 규칙 |
|:---|:---|:---|:---|
| SSH (전통) | 22 | TCP | ❌ **DENY 0.0.0.0/0** |
| Teleport Proxy | 443 | HTTPS | ✅ Public ALB only |
| Teleport Tunnel | 3024 | TCP | Internal (Reverse) |
| K8s API | 6443 | TCP | Internal NLB only |

---

## 3. RKE2 보안 최적화

### 3.1 Control Plane 격리

```hcl
# Internal NLB만 사용
enable_internal_nlb = true

# Public NLB는 Ingress(80/443)만 노출
enable_public_ingress_nlb = true
```

### 3.2 Node 보안 설정

```bash
# Golden Image 대응 (user-data)

# 1. Docker 비활성화 (RKE2 충돌 방지)
systemctl stop docker && systemctl disable docker

# 2. SSH 데몬 유지 (비상용)
# - Security Group에서 Port 22 차단 (평시)
# - Break Glass 시 SG 임시 오픈

# 3. Teleport SSH Agent (선택)
# - 멀티클라우드 고려 시: 활성화
# - AWS Only: 비활성화 (SSM 사용)
```

### 3.3 containerd 전용 (Docker 제거)

**이유:**
- RKE2는 내장 containerd 사용
- Docker 데몬은 불필요한 리소스 낭비
- 보안 패치 포인트 증가

**검증:**
```bash
# RKE2 노드 접속 후
systemctl status docker    # inactive (dead)
crictl ps                   # RKE2 컨테이너 목록
```

---

## 4. 운영 시나리오별 접근 방법

### 4.1 K8s 관리 (일상)

```bash
# Teleport 로그인
tsh login --proxy=teleport.dev.unifiedmeta.net

# K8s 클러스터 선택
tsh kube login meta-dev

# 이후 kubectl 자유 사용
kubectl get pods -A
kubectl logs -f pod/my-app
```

### 4.2 DB 서버 접속 (운영)

```bash
# Option A: Teleport SSH (Golden Image Agent 있을 때)
tsh ssh ubuntu@postgres.dev.unifiedmeta.net

# Option B: AWS SSM (AWS Only)
aws ssm start-session --target i-xxxxxxxxx

# Option C: Break Glass (최후 수단)
# 1. Console에서 SG 변경 (Port 22 허용)
# 2. ssh -i key.pem ubuntu@<public-ip>
```

### 4.3 RKE2 노드 디버깅 (비상)

```bash
# Option A: kubectl exec (권장)
kubectl get nodes
kubectl debug node/ip-10-0-1-5 -it --image=ubuntu

# Option B: SSM (AWS Only)
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*rke2*" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
aws ssm start-session --target $INSTANCE_ID

# Option C: Teleport SSH (Agent 활성화 시)
tsh ssh ubuntu@ip-10-0-1-5
```

---

## 5. Multi-Cloud 전략

### 5.1 클라우드별 Break Glass

| CSP | 주 접근 방법 | Break Glass |
|:---|:---|:---|
| **AWS** | Teleport + SSM | Serial Console |
| **GCP** | Teleport + IAP | Serial Console |
| **Azure** | Teleport + Bastion | Serial Console |
| **On-Prem** | Teleport (필수) | IPMI / iLO |

### 5.2 Port 22 정책

**권장:**
- **Port 22 유지** (글로벌 표준)
- **Security Group = DENY ALL** (기본)
- **Teleport = 주 접근 경로** (Reverse Tunnel)
- **Break Glass = 임시 SG 변경** (감사 로그 필수)

---

## 6. Compliance & Audit

### 6.1 ISMS-P 대응

| 요구사항 | 구현 |
|:---|:---|
| 비밀번호 대신 인증서 | ✅ Teleport Short-lived Cert |
| MFA 필수 | ✅ SSO (Google) + OTP |
| 세션 녹화 | ✅ Teleport S3 Recording |
| 접근 로그 | ✅ CloudTrail + Teleport Audit |

### 6.2 감사 증적 조회

```bash
# Teleport 세션 조회
tctl get events --type=session.start --format=json

# AWS SSM 세션 조회
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=StartSession
```

---

## 7. Golden Image 최적화 (최종 권장)

### 7.1 포함 항목

```
✅ Docker             # DB 서버용 (Docker Compose)
✅ SSM Agent          # AWS Break Glass
✅ Teleport Agent     # 멀티클라우드 SSH (선택)
✅ CloudWatch Agent   # 로그 수집
```

### 7.2 스택별 최적화

| 스택 | Docker | SSH | Teleport Agent |
|:---|:---:|:---:|:---:|
| **60-db** | ✅ 사용 | ✅ SG 차단 | ✅ 활성화 |
| **50-rke2** | ❌ 비활성화 | ✅ SG 차단 | ⚠️ 선택 |
| **15-teleport** | ❌ 불필요 | ✅ SG 차단 | ❌ 자기 자신 |

---

## 8. 참고 자료

- [Teleport Best Practices](https://goteleport.com/docs/production/)
- [AWS Security Best Practices](https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-standards-fsbp.html)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
