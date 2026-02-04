# 트러블슈팅 - Client VPN 스택 수동 리소스 제거

Terraform destroy 실패로 인해 AWS에 남아있는 Client VPN 관련 리소스를 수동으로 제거하는 방법을 정리합니다.

## 문제 상황

`15-vpn` 스택의 `terraform destroy`가 실패하여 AWS에 Client VPN Endpoint 및 관련 리소스들이 남아있는 상태입니다.

```bash
make destroy STACK=15-vpn ENV=dev
# Error: ... (destroy 실패)
```

VPN을 더 이상 사용하지 않기로 결정했으나, Terraform 상태가 망가졌거나 스택 디렉토리가 삭제되어 정상적인 destroy가 불가능한 경우입니다.

## 원인

Client VPN Endpoint는 다음과 같은 복잡한 종속성 구조를 가지고 있습니다:

```
Client VPN Endpoint
├── Network Association (Subnet 연결)
│   └── VPN Route (자동 생성)
├── Authorization Rule (접근 제어)
└── Security Group (연결됨)
    └── ACM Certificates (Server, Client)
```

Terraform destroy가 실패하는 주요 원인:
1. **종속성 순서 문제**: 종속 리소스가 먼저 삭제되지 않으면 상위 리소스 삭제 불가
2. **비동기 삭제**: Network Association 삭제가 완료되기 전에 다음 단계로 넘어가면 실패
3. **타임아웃**: VPN Endpoint 삭제는 수 분이 걸릴 수 있어 Terraform 타임아웃 발생 가능

## 해결 방법

### 1단계: 리소스 파악

스택 디렉토리가 없는 경우, Git 히스토리를 통해 생성된 리소스를 파악합니다:

```bash
# VPN 스택 추가 커밋 찾기
git log --all --oneline --grep="vpn" -i | head -10

# 커밋에서 main.tf 확인
git show <commit-hash>:stacks/dev/15-vpn/main.tf
```

### 2단계: AWS 리소스 확인

aws-vault 또는 AWS CLI로 실제 남아있는 리소스를 확인합니다:

```bash
# VPN Endpoint 확인
aws-vault exec devops -- aws ec2 describe-client-vpn-endpoints \
  --query 'ClientVpnEndpoints[*].[ClientVpnEndpointId,Tags[?Key==`Name`].Value|[0],Status.Code]' \
  --output table

# Security Group 확인
aws-vault exec devops -- aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=*vpn*" \
  --query 'SecurityGroups[*].[GroupId,GroupName]' \
  --output table

# ACM Certificates 확인
aws-vault exec devops -- aws acm list-certificates \
  --query 'CertificateSummaryList[?contains(DomainName,`vpn`)].[CertificateArn,DomainName]' \
  --output table
```

### 3단계: 종속 리소스 삭제 (중요: 순서 준수)

**매우 중요**: 반드시 아래 순서대로 삭제해야 합니다.

```bash
# VPN_ENDPOINT_ID를 위에서 확인한 값으로 설정
VPN_ENDPOINT_ID="cvpn-endpoint-xxxxxxxxx"

# 1. Authorization Rule 삭제
aws-vault exec devops -- aws ec2 revoke-client-vpn-ingress \
  --client-vpn-endpoint-id $VPN_ENDPOINT_ID \
  --target-network-cidr 10.0.0.0/16 \
  --revoke-all-groups

# 2. Network Association 조회
aws-vault exec devops -- aws ec2 describe-client-vpn-target-networks \
  --client-vpn-endpoint-id $VPN_ENDPOINT_ID \
  --query 'ClientVpnTargetNetworks[*].[AssociationId,TargetNetworkId,Status.Code]' \
  --output table

# ASSOCIATION_ID를 위에서 확인한 값으로 설정
ASSOCIATION_ID="cvpn-assoc-xxxxxxxxx"

# 3. Network Association 삭제
aws-vault exec devops -- aws ec2 disassociate-client-vpn-target-network \
  --client-vpn-endpoint-id $VPN_ENDPOINT_ID \
  --association-id $ASSOCIATION_ID
```

#### 중요: 삭제 대기 시간

Network Association 삭제는 **2~5분 정도** 소요됩니다. 다음 단계로 넘어가기 전에 반드시 삭제 완료를 확인해야 합니다:

```bash
# 삭제 상태 확인 (빈 배열이 나올 때까지 반복)
aws-vault exec devops -- aws ec2 describe-client-vpn-target-networks \
  --client-vpn-endpoint-id $VPN_ENDPOINT_ID

# 결과가 {"ClientVpnTargetNetworks": []} 이면 다음 단계 진행
```

### 4단계: VPN Endpoint 삭제

Network Association이 완전히 삭제된 후에만 VPN Endpoint를 삭제할 수 있습니다:

```bash
# VPN Endpoint 삭제
aws-vault exec devops -- aws ec2 delete-client-vpn-endpoint \
  --client-vpn-endpoint-id $VPN_ENDPOINT_ID

# 삭제 확인 (30초~1분 소요)
aws-vault exec devops -- aws ec2 describe-client-vpn-endpoints \
  --client-vpn-endpoint-ids $VPN_ENDPOINT_ID

# InvalidClientVpnEndpointId.NotFound 에러가 나오면 삭제 완료
```

### 5단계: 독립 리소스 정리

VPN Endpoint가 삭제된 후 종속성이 없는 리소스들을 정리합니다:

```bash
# Security Group 삭제
SG_ID="sg-xxxxxxxxx"  # 2단계에서 확인한 값
aws-vault exec devops -- aws ec2 delete-security-group --group-id $SG_ID

# ACM Certificates 삭제
aws-vault exec devops -- aws acm delete-certificate --certificate-arn <SERVER_CERT_ARN>
aws-vault exec devops -- aws acm delete-certificate --certificate-arn <CLIENT_CERT_ARN>

# CloudWatch Log Group 삭제 (있는 경우)
aws-vault exec devops -- aws logs delete-log-group --log-group-name "/aws/vpn/<log-group-name>"
```

### 6단계: 검증

모든 리소스가 제거되었는지 확인합니다:

```bash
# VPN Endpoint 확인 (결과: [])
aws-vault exec devops -- aws ec2 describe-client-vpn-endpoints \
  --query 'ClientVpnEndpoints[?Tags[?Key==`Name`&&contains(Value,`meta-dev`)]]'

# Security Group 확인 (결과: [])
aws-vault exec devops -- aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=*vpn*" --query 'SecurityGroups[*].GroupId'

# ACM Certificates 확인 (결과: [])
aws-vault exec devops -- aws acm list-certificates \
  --query 'CertificateSummaryList[?contains(DomainName,`vpn`)]'
```

모든 명령이 빈 배열 `[]`을 반환하면 완전히 제거된 것입니다.

### 7단계: 코드 정리

AWS 리소스 삭제 후 코드베이스에서 관련 로직을 제거합니다:

```bash
# 1. check-status.sh에서 VPN 상태 체크 로직 제거
vim scripts/common/check-status.sh
# elif [[ "$STACK" == "15-vpn" ]] 블록 전체 삭제

# 2. VPN 클라이언트 설정 가이드 삭제
rm docs/guides/vpn-client-setup.md

# 3. 변경 사항 커밋
git add -A
git commit -m "chore: Remove 15-vpn stack and clean up related code"
```

## 자동화 스크립트 (옵션)

반복적인 VPN 리소스 정리를 위한 자동화 스크립트:

```bash
#!/bin/bash
# scripts/cleanup/remove-vpn-stack.sh

set -e

ENV=${1:-dev}
PROJECT=${2:-meta}

echo "Cleaning up Client VPN resources for $ENV-$PROJECT..."

# VPN Endpoint 찾기
VPN_ENDPOINT_ID=$(aws ec2 describe-client-vpn-endpoints \
  --query "ClientVpnEndpoints[?Tags[?Key=='Name'&&Value=='$ENV-$PROJECT-client-vpn']].ClientVpnEndpointId" \
  --output text)

if [ -z "$VPN_ENDPOINT_ID" ]; then
  echo "No VPN Endpoint found. Exiting."
  exit 0
fi

echo "Found VPN Endpoint: $VPN_ENDPOINT_ID"

# Authorization Rule 삭제
echo "Revoking authorization rules..."
aws ec2 revoke-client-vpn-ingress \
  --client-vpn-endpoint-id $VPN_ENDPOINT_ID \
  --target-network-cidr 10.0.0.0/16 \
  --revoke-all-groups || true

# Network Association 삭제
ASSOC_ID=$(aws ec2 describe-client-vpn-target-networks \
  --client-vpn-endpoint-id $VPN_ENDPOINT_ID \
  --query 'ClientVpnTargetNetworks[0].AssociationId' \
  --output text)

if [ -n "$ASSOC_ID" ] && [ "$ASSOC_ID" != "None" ]; then
  echo "Disassociating network: $ASSOC_ID"
  aws ec2 disassociate-client-vpn-target-network \
    --client-vpn-endpoint-id $VPN_ENDPOINT_ID \
    --association-id $ASSOC_ID
  
  # 삭제 완료 대기
  echo "Waiting for disassociation to complete (this may take 2-5 minutes)..."
  while true; do
    STATUS=$(aws ec2 describe-client-vpn-target-networks \
      --client-vpn-endpoint-id $VPN_ENDPOINT_ID \
      --query 'ClientVpnTargetNetworks[0].Status.Code' \
      --output text 2>/dev/null || echo "deleted")
    
    if [ "$STATUS" == "None" ] || [ "$STATUS" == "deleted" ]; then
      break
    fi
    echo "  Status: $STATUS (waiting...)"
    sleep 10
  done
fi

# VPN Endpoint 삭제
echo "Deleting VPN Endpoint..."
aws ec2 delete-client-vpn-endpoint --client-vpn-endpoint-id $VPN_ENDPOINT_ID

echo "Waiting for VPN Endpoint deletion..."
sleep 30

# Security Group 삭제
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=$ENV-$PROJECT-vpn-endpoint-sg" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
  echo "Deleting Security Group: $SG_ID"
  aws ec2 delete-security-group --group-id $SG_ID
fi

# ACM Certificates 삭제
echo "Deleting ACM Certificates..."
aws acm list-certificates \
  --query 'CertificateSummaryList[?contains(DomainName,`vpn`)].CertificateArn' \
  --output text | while read -r cert_arn; do
    echo "  Deleting: $cert_arn"
    aws acm delete-certificate --certificate-arn $cert_arn
  done

echo "✅ VPN resources cleanup completed!"
```

사용 방법:
```bash
chmod +x scripts/cleanup/remove-vpn-stack.sh
aws-vault exec devops -- ./scripts/cleanup/remove-vpn-stack.sh dev meta
```

## 주요 주의 사항

⚠️ **삭제 순서는 절대적입니다**
1. Authorization Rule & Routes (빠름)
2. Network Association (2-5분 소요, 완료 대기 필수)
3. VPN Endpoint (30초-1분 소요)
4. Security Group & ACM Certificates (즉시)

⚠️ **비동기 삭제 대기**
- Network Association 삭제는 AWS가 ENI를 정리하는 시간이 필요합니다
- 상태가 `disassociating`에서 완전히 사라질 때까지 기다려야 합니다
- 조급하게 다음 단계로 넘어가면 `InvalidParameterValue` 에러 발생

⚠️ **VPN Route는 자동 삭제됨**
- Network Association이 삭제되면 연결된 Route는 자동으로 제거됩니다
- Route를 수동으로 삭제하려고 시도하면 `InvalidClientVpnRouteNotFound` 에러 발생

## 실제 사례: 2026-02-04 15-vpn 스택 제거

**상황**: 15-vpn 스택의 destroy 실패로 다음 리소스들이 남아있었음
- VPN Endpoint: `cvpn-endpoint-0984e3e4a355360fa`
- Network Association: `cvpn-assoc-0e974f3a5b99f7c67`
- Security Group: `sg-04d7429d9db67f15f`
- ACM Certificates: 2개 (vpn-server.unifiedmeta.net, vpn-client.unifiedmeta.net)

**해결 과정**:
1. Git 히스토리에서 커밋 `9abc9d7`을 통해 리소스 구조 파악
2. aws-vault로 인증 후 실제 리소스 확인
3. Authorization Rule 삭제 → Network Association 삭제 (3분 대기)
4. VPN Endpoint 삭제 (30초 대기)
5. Security Group, ACM Certificates 삭제
6. 검증 완료 후 `check-status.sh`에서 VPN 관련 코드 84줄 제거

**소요 시간**: 약 5분 (대부분 Network Association 삭제 대기 시간)

**비용 절감**: VPN Endpoint 시간당 요금 절감, 미사용 리소스 정리

## 교훈

1. **종속성 이해의 중요성**: Client VPN의 복잡한 종속성 구조를 정확히 이해해야 수동 삭제 가능
2. **비동기 삭제 대기**: AWS 리소스 삭제는 비동기적이므로 각 단계마다 완료 확인 필수
3. **자동화의 가치**: 반복적인 작업은 스크립트로 자동화하여 실수 방지
4. **상태 검증**: 각 단계마다 리소스 상태를 확인하여 다음 단계 진행 여부 판단
5. **코드 정리**: AWS 리소스 삭제 후 코드베이스의 참조도 함께 정리하여 일관성 유지

---

## 관련 문서

- [AWS Client VPN Endpoint 공식 문서](https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/what-is.html)
- [Terraform aws_ec2_client_vpn_endpoint](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_client_vpn_endpoint)
- Infrastructure Security Hardening KI: `access_control/aws_vpn_strategy.md`
