# AWS Client VPN 연결 가이드

> 개발팀용 VPN 클라이언트 설정 및 연결 방법

---

## 1. 사전 요구사항

### 1.1 AWS VPN Client 설치

| OS | 다운로드 링크 |
|:---|:---|
| **macOS** | https://aws.amazon.com/vpn/client-vpn-download/ |
| **Windows** | https://aws.amazon.com/vpn/client-vpn-download/ |
| **Linux** | OpenVPN 클라이언트 사용 (`sudo apt install openvpn`) |

### 1.2 VPN 설정 파일 받기

인프라 관리자에게 `vpn-config.ovpn` 파일을 요청하거나, 직접 생성합니다:

```bash
cd stacks/dev/15-vpn
./generate-ovpn.sh
```

---

## 2. VPN 연결 (AWS VPN Client)

### 2.1 프로필 추가

1. AWS VPN Client 실행
2. **File > Manage Profiles > Add Profile**
3. `vpn-config.ovpn` 파일 선택
4. 프로필 이름 입력 (예: `Dev VPN`)

### 2.2 연결

1. 추가한 프로필 선택
2. **Connect** 클릭
3. 연결 완료 대기 (10~30초)

### 2.3 연결 확인

```bash
# VPC 내부 리소스 접근 테스트
ping 10.0.x.x  # Bastion 또는 K8s 노드 Private IP

# K8s 연결 확인
kubectl get nodes

# ArgoCD 접속 (Private IP)
open https://10.0.x.x:30443
```

---

## 3. VPN 연결 (OpenVPN CLI - macOS/Linux)

### 3.1 OpenVPN 설치

```bash
# macOS
brew install openvpn

# Ubuntu/Debian
sudo apt install openvpn
```

### 3.2 연결

```bash
# 포그라운드 실행
sudo openvpn --config vpn-config.ovpn

# 백그라운드 실행
sudo openvpn --config vpn-config.ovpn --daemon
```

### 3.3 연결 해제

```bash
sudo killall openvpn
```

---

## 4. 트러블슈팅

### 연결 실패: `TLS Error`

**원인**: 인증서 만료 또는 손상

**해결**:
```bash
# 인증서 재생성
cd stacks/dev/15-vpn
terraform taint tls_private_key.client
terraform apply
./generate-ovpn.sh
```

### 연결 성공했지만 Private IP 접근 불가

**원인**: 라우팅 문제

**해결**:
```bash
# 라우팅 테이블 확인
netstat -rn | grep 10.0

# VPN 터널 인터페이스 확인
ifconfig | grep -A 5 utun
```

### DNS 해석 안됨

**원인**: VPN DNS가 VPC DNS로 설정되지 않음

**해결**:
```bash
# /etc/resolv.conf 확인 (Linux)
cat /etc/resolv.conf

# macOS DNS 확인
scutil --dns
```

---

## 5. 보안 주의사항

1. **vpn-config.ovpn 파일 보관**
   - 이 파일에는 Private Key가 포함되어 있습니다
   - 안전하게 보관하고 공유하지 마세요

2. **연결 로그 모니터링**
   - 관리자는 CloudWatch에서 모든 VPN 연결 기록을 확인할 수 있습니다
   - 로그 그룹: `/aws/vpn/dev-*-client-vpn`

3. **세션 만료**
   - VPN 세션은 8시간 후 자동 만료됩니다
   - 만료 시 재연결하세요

---

## 6. 연결 후 접근 가능한 서비스

| 서비스 | Private IP | 포트 |
|:---|:---|:---:|
| ArgoCD | 10.0.x.x | 30443 |
| Rancher | 10.0.x.x | 30443 |
| Grafana | 10.0.x.x | 30080 |
| Longhorn | 10.0.x.x | 30080 |
| Harbor | 10.0.x.x | 443 |
| Bastion SSH | 10.0.x.x | 22 |

> **Note**: 실제 IP는 `kubectl get nodes -o wide` 또는 Terraform output에서 확인하세요.

---

## 7. 참고 명령어

```bash
# VPN 상태 확인 (AWS CLI)
aws ec2 describe-client-vpn-connections \
  --client-vpn-endpoint-id cvpn-endpoint-xxxxx

# 활성 연결 수 확인
aws cloudwatch get-metric-statistics \
  --namespace AWS/ClientVPN \
  --metric-name ActiveConnectionsCount \
  --dimensions Name=Endpoint,Value=cvpn-endpoint-xxxxx \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Maximum
```
