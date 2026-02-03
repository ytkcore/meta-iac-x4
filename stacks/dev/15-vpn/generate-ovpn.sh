#!/bin/bash
#------------------------------------------------------------------------------
# VPN 클라이언트 설정 파일 생성 스크립트
#
# 사용법: ./generate-ovpn.sh
# 결과:  vpn-config.ovpn 파일 생성
#------------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# VPN Endpoint ID 가져오기
VPN_ENDPOINT_ID=$(terraform output -raw vpn_endpoint_id 2>/dev/null)

if [ -z "$VPN_ENDPOINT_ID" ]; then
  echo "Error: VPN Endpoint ID를 가져올 수 없습니다."
  echo "terraform apply가 완료되었는지 확인하세요."
  exit 1
fi

echo "VPN Endpoint ID: $VPN_ENDPOINT_ID"

# 기본 설정 파일 다운로드
echo "VPN 클라이언트 설정 파일 다운로드 중..."
aws ec2 export-client-vpn-client-configuration \
  --client-vpn-endpoint-id "$VPN_ENDPOINT_ID" \
  --output text > vpn-config.ovpn

# 인증서 추가
echo "클라이언트 인증서 추가 중..."

echo "" >> vpn-config.ovpn
echo "<cert>" >> vpn-config.ovpn
cat generated/client.crt >> vpn-config.ovpn
echo "</cert>" >> vpn-config.ovpn

echo "" >> vpn-config.ovpn
echo "<key>" >> vpn-config.ovpn
cat generated/client.key >> vpn-config.ovpn
echo "</key>" >> vpn-config.ovpn

echo ""
echo "=========================================="
echo "VPN 설정 파일 생성 완료!"
echo "=========================================="
echo ""
echo "파일 위치: $SCRIPT_DIR/vpn-config.ovpn"
echo ""
echo "사용 방법:"
echo "1. AWS VPN Client 설치 (https://aws.amazon.com/vpn/client-vpn-download/)"
echo "2. File > Manage Profiles > Add Profile"
echo "3. vpn-config.ovpn 파일 선택"
echo "4. Connect 클릭"
echo ""
echo "=========================================="
