# Golden Image 구성 명세서

> `meta-golden-image-al2023-*` 기본 설정 및 포함 항목

---

## 1. 기본 정보

| 항목 | 값 |
|:---|:---|
| **Base OS** | Amazon Linux 2023 |
| **Architecture** | x86_64 |
| **Image Naming** | `meta-golden-image-al2023-YYYYMMDD-HHMMSS` |
| **Update Policy** | 월 1회 (보안 패치) |
| **Retention** | 최근 3개 버전 유지 |

---

## 2. 사전 설치 소프트웨어

### 2.1 Container Runtime

| 컴포넌트 | 버전 | 용도 | 기본 상태 |
|:---|:---|:---|:---|
| **Docker** | 24.x | 컨테이너 실행 (DB, Harbor) | ✅ Enabled |
| **Docker Compose** | 2.x | 멀티 컨테이너 관리 | ✅ Installed |

### 2.2 AWS 에이전트

| 컴포넌트 | 용도 | 기본 상태 | 비고 |
|:---|:---|:---|:---|
| **SSM Agent** | AWS Systems Manager 접근 | ✅ Enabled | Break Glass 필수 (항상 활성) |
| **CloudWatch Agent** | 로그/메트릭 수집 | ❌ Disabled | 비용 최적화 (스택별 On/Off) |
| **AWS CLI** | AWS 리소스 관리 | ✅ Installed | v2 |

> [!NOTE]
> **스택별 On/Off 제어**: CloudWatch, Docker, Teleport Agent는 `10-golden-image` 스택의 SSM Parameter 또는 각 스택의 user-data에서 활성화/비활성화할 수 있습니다.

### 2.3 Teleport Agent (선택적)

| 컴포넌트 | 용도 | 기본 상태 | 활성화 조건 |
|:---|:---|:---|:---|
| **Teleport SSH Agent** | 중앙 집중 SSH 접근 | ⚠️ Installed | 스택별 user-data에서 제어 |

---

## 3. 시스템 설정

### 3.1 SSH 설정

| 항목 | 기본값 | 변경 가능 | 변경 시점 |
|:---|:---|:---|:---|
| **Port** | 22 | ✅ Yes | `make init` 입력 → user-data 반영 |
| **PasswordAuthentication** | no | ❌ No | - |
| **PubkeyAuthentication** | yes | ❌ No | - |
| **PermitRootLogin** | no | ❌ No | - |
| **MaxAuthTries** | 3 | ⚠️ Yes | 수동 |
| **ClientAliveInterval** | 300 | ⚠️ Yes | 수동 |

> [!NOTE]
> **SSH 포트 동적 변경**: Golden Image는 Port 22로 빌드되지만, `make init` 실행 시 사용자가 입력한 포트(22 또는 22022)가 user-data를 통해 인스턴스 부팅 시 자동 적용됩니다.

**SSH 강화 설정 (기본 포함):**
```bash
# /etc/ssh/sshd_config
Protocol 2
PermitEmptyPasswords no
X11Forwarding no
MaxAuthTries 3
IgnoreRhosts yes
HostbasedAuthentication no
PermitUserEnvironment no
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,diffie-hellman-group-exchange-sha256
```

### 3.2 방화벽 (firewalld)

| 항목 | 기본값 | 비고 |
|:---|:---|:---|
| **상태** | Disabled | Security Group 사용 |
| **대체** | AWS Security Group | Network-level 제어 |

### 3.3 SELinux

| 항목 | 기본값 | 비고 |
|:---|:---|:---|
| **모드** | Enforcing | Amazon Linux 2023 기본값 |
| **정책** | targeted | - |

### 3.4 시간 동기화

| 항목 | 설정 | 비고 |
|:---|:---|:---|
| **NTP 서비스** | chrony | systemd-timesyncd 대체 |
| **NTP 서버** | Amazon Time Sync Service | 169.254.169.123 |
| **Timezone** | UTC | 모든 인스턴스 표준 |

---

## 4. 보안 강화

### 4.1 커널 파라미터

| 항목 | 값 | 목적 |
|:---|:---|:---|
| `net.ipv4.ip_forward` | 0 | IP 포워딩 비활성화 |
| `net.ipv4.conf.all.send_redirects` | 0 | ICMP 리디렉트 차단 |
| `net.ipv4.conf.all.accept_redirects` | 0 | ICMP 리디렉트 수신 차단 |
| `net.ipv4.icmp_echo_ignore_all` | 0 | Ping 허용 (디버깅용) |
| `kernel.randomize_va_space` | 2 | ASLR 활성화 |

### 4.2 사용자 계정

| 계정 | 용도 | sudo 권한 | 기본 셸 |
|:---|:---|:---|:---|
| **ec2-user** | AL2023 기본 | ✅ Yes | bash |
| **ssm-user** | SSM Session Manager | ✅ Yes | bash |
| **root** | 시스템 관리 | - | bash |

### 4.3 패키지 관리

| 항목 | 설정 |
|:---|:---|
| **자동 업데이트** | Disabled (관리형) |
| **보안 패치** | Golden Image 빌드 시 적용 |
| **추가 Repo** | EPEL (선택적) |

---

## 5. 모니터링 및 로깅

### 5.1 CloudWatch Logs

| 로그 파일 | CloudWatch Log Group | Retention |
|:---|:---|:---|
| `/var/log/messages` | `/aws/ec2/{env}-{stack}/system` | 7일 |
| `/var/log/secure` | `/aws/ec2/{env}-{stack}/auth` | 30일 |
| `/var/log/user-data.log` | `/aws/ec2/{env}-{stack}/bootstrap` | 7일 |

### 5.2 CloudWatch Metrics

| 메트릭 | 수집 주기 | 용도 |
|:---|:---|:---|
| CPU Utilization | 1분 | 성능 모니터링 |
| Memory Used | 1분 | 메모리 부족 감지 |
| Disk Used | 5분 | 디스크 공간 경고 |

---

## 6. 설치 도구

### 6.1 시스템 유틸리티

| 도구 | 용도 |
|:---|:---|
| `curl`, `wget` | HTTP 다운로드 |
| `git` | 버전 관리 |
| `vim`, `nano` | 텍스트 편집 |
| `htop` | 프로세스 모니터링 |
| `jq` | JSON 처리 |
| `unzip`, `tar` | 압축 해제 |

### 6.2 네트워크 도구

| 도구 | 용도 |
|:---|:---|
| `netcat (nc)` | 포트 스캔/테스트 |
| `telnet` | 연결 테스트 |
| `dig`, `nslookup` | DNS 조회 |
| `traceroute` | 네트워크 경로 추적 |
| `tcpdump` | 패킷 캡처 |

---

## 7. 스택별 활성화 정책

| 컴포넌트 | 60-db | 50-rke2 | 15-teleport | 30-bastion | 40-harbor |
|:---|:---:|:---:|:---:|:---:|:---:|
| **Docker** | ✅ Active | ❌ Disabled | ❌ Disabled | ⚠️ Optional | ✅ Active |
| **Teleport SSH Agent** | ✅ Active | ❌ Disabled | ❌ N/A | ⚠️ Optional | ❌ Disabled |
| **Teleport Kube Agent** | - | ✅ **Pod** | - | - | - |
| **SSM Agent** | ✅ Active | ✅ Active | ✅ Active | ✅ Active | ✅ Active |
| **CloudWatch Agent** | ✅ Active | ❌ Disabled | ✅ Active | ❌ Disabled | ⚠️ Prod Only |
| **SSH Port** | var | var | var | var | var |

> [!IMPORTANT]
> **스택별 제어 방법**: 각 스택의 `terraform.tfvars` 또는 `user-data`에서 컴포넌트를 활성화/비활성화합니다.
> ```hcl
> # 예시: 50-rke2에서 Docker 비활성화
> # user-data.sh에서:
> systemctl disable docker
> ```

> **비활성화 방법**: user-data 스크립트에서 `systemctl disable <service>` 실행

---

## 8. user-data 변수 주입

Golden Image는 불변이지만, 인스턴스 부팅 시 user-data로 다음 항목을 동적으로 설정할 수 있습니다.

| 변수 | 설정 항목 | 예시 |
|:---|:---|:---|
| `${ssh_port}` | SSH 포트 변경 | 22 → 22022 |
| `${hostname}` | 호스트네임 설정 | `db-postgres-01` |
| `${teleport_proxy}` | Teleport 서버 주소 | `teleport.dev.example.com` |
| `${docker_compose_file}` | Docker Compose YAML | DB 컨테이너 정의 |

---

## 9. 빌드 프로세스 (참고)

```bash
# 1. Base AMI (Amazon Linux 2023 최신)
# 2. 시스템 업데이트
dnf update -y

# 3. 소프트웨어 설치
dnf install -y docker aws-cli jq vim htop

# 4. 보안 강화
# - SSH 설정 수정
# - 커널 파라미터 조정
# - 불필요 서비스 비활성화

# 5. 에이전트 설치
# - SSM Agent (기본 포함)
# - CloudWatch Agent
# - Teleport Agent

# 6. 정리 및 AMI 생성
# - 로그 파일 삭제
# - 기계 ID 초기화
# - AMI 스냅샷
```

---

## 10. 유지보수

### 10.1 업데이트 주기

| 항목 | 주기 | 트리거 |
|:---|:---|:---|
| **보안 패치** | 월 1회 | CVE 발표 |
| **버전 업그레이드** | 분기 1회 | Docker, Teleport |
| **Base OS 업그레이드** | 반기 1회 | Amazon Linux 릴리스 |

### 10.2 검증 항목

| 항목 | 방법 |
|:---|:---|
| **SSM 접근** | `aws ssm start-session` |
| **Docker 실행** | `docker run hello-world` |
| **SSH 접속** | Port 22 Listen 확인 |
| **CloudWatch 로그** | 부팅 로그 수집 확인 |

---

## 부록: 상세 설정 파일 위치

| 설정 | 파일 경로 |
|:---|:---|
| SSH | `/etc/ssh/sshd_config` |
| CloudWatch Agent | `/opt/aws/amazon-cloudwatch-agent/etc/config.json` |
| Docker | `/etc/docker/daemon.json` |
| Teleport Agent | `/etc/teleport.yaml` |
| 커널 파라미터 | `/etc/sysctl.d/99-security.conf` |
