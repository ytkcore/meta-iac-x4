# Golden Image 최적화 전략 - 전체 스택 분석

## 스택별 Golden Image 활용 현황 및 최적화 방안

| Stack | EC2 사용 | Golden Image | Docker | Teleport Agent | SSH | 최적화 전략 |
|:---|:---:|:---:|:---:|:---:|:---:|:---|
| **00-network** | ❌ | - | - | - | - | VPC/네트워크만 생성, EC2 없음 |
| **10-security** | ❌ | - | - | - | - | Security Group만 생성, EC2 없음 |
| **15-teleport** | ✅ | ✅ 자동 Lookup | ❌ 불필요 | ❌ 자기 자신 | ✅ SG 차단 | Docker 비활성화 |
| **20-waf** | ❌ | - | - | - | - | CloudFront/WAF만, EC2 없음 |
| **30-bastion** | ✅ | ⚠️ 미확인 | ⚠️ 미확인 | ⚠️ 선택 | ✅ 제한적 허용 | 검토 필요 |
| **40-harbor** | ✅ | ⚠️ 미확인 | ✅ 필수 | ❌ 불필요 | ✅ SG 차단 | 검토 필요 |
| **50-rke2** | ✅ | ✅ 자동 Lookup | ❌ **비활성화** | ❌ Pod로 대체 | ✅ SG 차단 | Docker 비활성화 완료 |
| **55-bootstrap** | ❌ | - | - | - | - | GitOps 설정만, EC2 없음 |
| **60-db** | ✅ | ✅ 자동 Lookup | ✅ 필수 | ✅ 활성화 | ✅ SG 차단 | 표준 (모범 사례) |
| **70-observability** | ❌ | - | - | - | - | K8s 리소스만, EC2 없음 |

---

## 컴포넌트별 상세 정책

### 1. Golden Image 포함 항목

| 컴포넌트 | 포함 여부 | 사용 목적 |
|:---|:---:|:---|
| **Docker** | ✅ | DB 서버(60-db), Harbor(40-harbor) |
| **SSM Agent** | ✅ | Break Glass 접근 (모든 EC2) |
| **Teleport Agent** | ✅ | SSH 접근 제어 (선택적 활성화) |
| **CloudWatch Agent** | ✅ | 로그/메트릭 수집 |
| **기본 보안 설정** | ✅ | SSH 강화, 방화벽 등 |

### 2. 스택별 최적화 전략

#### ✅ 60-db (표준 - 모든 기능 활성화)
```bash
# Golden Image 그대로 사용
✅ Docker: 활성화 (PostgreSQL, Neo4j 컨테이너)
✅ Teleport Agent: 활성화 (tsh ssh 접근)
✅ SSM Agent: 활성화 (Break Glass)
✅ SSH Port: 22 (SG 차단)
```

#### ✅ 50-rke2 (최적화 - 불필요 서비스 비활성화)
```bash
# user-data에서 선택적 비활성화
❌ Docker: systemctl disable docker
❌ Teleport SSH Agent: 사용 안 함 (Kube Agent Pod 사용)
✅ SSM Agent: 활성화 (Break Glass)
✅ SSH Port: 22 (SG 차단)
```

#### ✅ 15-teleport (최적화 - Teleport 서버)
```bash
# Teleport 서버 자체이므로 Agent 불필요
❌ Docker: 불필요
❌ Teleport Agent: 불필요 (자기 자신)
✅ SSM Agent: 활성화 (Break Glass)
✅ SSH Port: 22 (SG 차단)
```

#### ⚠️ 40-harbor (검토 필요)
```bash
# 현재 상태 확인 필요
? Golden Image 사용 여부
✅ Docker: 필수 (Harbor 컨테이너)
❌ Teleport Agent: 불필요 (K8s 관리)
✅ SSM Agent: 권장
✅ SSH Port: 22 (SG 차단)
```

#### ⚠️ 30-bastion (검토 필요)
```bash
# Bastion 역할 재검토 필요
? Golden Image 사용 여부
? Teleport로 완전 대체 가능 여부
✅ SSM Agent: 필수 (Break Glass)
? SSH Port: 변경 고려 (bastion 특성상)
```

---

## 3. SSH 포트 정책 (전체 스택 공통)

### 기본 정책
```hcl
# env.tfvars (프로젝트 기본값)
ssh_port        = 22      # 표준 포트 유지
ssh_port_policy = "standard"

# Security Group (모든 스택)
ingress {
  from_port   = var.ssh_port
  to_port     = var.ssh_port
  protocol    = "tcp"
  cidr_blocks = []  # DENY ALL (기본값)
}
```

### 고객사별 커스터마이징
```hcl
# 대기업 고객사
ssh_port = 22

# 중소기업 고객사
ssh_port = 22022
```

---

## 4. Teleport Agent 배치 전략

| 대상 | Agent 유형 | 배치 위치 | 우선순위 |
|:---|:---|:---|:---|
| **60-db** | SSH Agent | Golden Image (systemd) | ✅ 필수 |
| **50-rke2** | Kube Agent | K8s Pod | ✅ 필수 |
| **50-rke2 Nodes** | SSH Agent | Golden Image (비활성화) | ❌ 불필요 |
| **40-harbor** | SSH Agent | Golden Image (선택) | ⚠️ 검토 |
| **30-bastion** | SSH Agent | 검토 필요 | ⚠️ 검토 |
| **15-teleport** | - | 불필요 (자기 자신) | ❌ 불필요 |

---

## 5. 구현 상태 (Implementation Status)

| 항목 | 상태 | 비고 |
|:---|:---:|:---|
| **60-db Golden Image Lookup** | ✅ 완료 | 이미 구현됨 |
| **15-teleport Golden Image Lookup** | ✅ 완료 | 구현 완료 (이번에) |
| **50-rke2 Golden Image Lookup** | ✅ 완료 | 구현 완료 (이번에) |
| **50-rke2 Docker 비활성화** | ✅ 완료 | user-data 수정 완료 |
| **Teleport Kube Agent** | ✅ 완료 | teleport-agent.yaml 생성 |
| **SSH Port 변수화** | ⏳ 대기 | 다음 단계 |
| **40-harbor 검토** | ⏳ 대기 | 현황 파악 필요 |
| **30-bastion 검토** | ⏳ 대기 | Teleport 대체 가능성 검토 |

---

## 6. 다음 단계 (Next Actions)

### Priority 1: SSH 포트 정책 구현
```bash
# 1. 공통 변수 추가 (env.tfvars)
ssh_port = 22  # default

# 2. Security Group 모듈 업데이트
# modules/security-group/* 에 ssh_port 변수 추가

# 3. Golden Image user-data
# /etc/ssh/sshd_config의 Port를 변수화
```

### Priority 2: 미확인 스택 검토
- [ ] 40-harbor: Golden Image 사용 여부 확인
- [ ] 30-bastion: 존재 이유 및 Teleport 대체 가능성 검토

### Priority 3: Teleport 운영 자동화
- [ ] Kube Agent 토큰 자동 생성 스크립트
- [ ] 초기 관리자 자동 생성 스크립트
- [ ] 운영 매뉴얼 배포

---

## 7. 권장 사항 요약

### ✅ DO (권장)
1. **모든 EC2에 Golden Image 사용** (자동 Lookup)
2. **SSH Port 22 유지** (SG로 차단)
3. **Docker는 필요한 곳만** (DB, Harbor)
4. **Teleport Agent는 선택적** (용도별 활성화)
5. **SSM Agent는 항상** (Break Glass)

### ❌ DON'T (비권장)
1. ~~SSH Port를 스택마다 다르게~~
2. ~~Golden Image 없이 Public AMI 직접 사용~~
3. ~~RKE2에서 Docker 실행~~
4. ~~모든 서버에 Teleport Agent 강제~~
5. ~~SSH를 완전히 제거~~

---

## 부록: 검증 스크립트

```bash
# Golden Image 사용 확인
terraform -chdir=stacks/dev/60-db output -json | \
  jq -r '.postgres_ami_id.value'

# Docker 상태 확인 (RKE2)
aws ssm start-session --target <rke2-instance-id>
systemctl status docker  # inactive (dead) 확인

# Teleport Agent 상태 확인
kubectl get pods -n teleport
tsh kube ls
```
