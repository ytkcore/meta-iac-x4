#!/bin/bash
# scripts/common/check-ami.sh

set -e

# Colors
if [ -t 1 ]; then
  GREEN='\033[32m'
  RED='\033[31m'
  YELLOW='\033[33m'
  CYAN='\033[36m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  GREEN='' RED='' YELLOW='' CYAN='' BOLD='' NC=''
fi

echo -e "${CYAN}[AMI Check]${NC} 프로젝트 전역 골든 이미지를 확인합니다..."

# Check if Packer is installed
if ! command -v packer &> /dev/null; then
  echo -e "${YELLOW}Warning:${NC} Packer가 설치되어 있지 않습니다. 빌드가 필요할 경우 설치가 선행되어야 합니다."
  # brew install packer # 필요 시 활성화
fi

# Helper for AWS CLI with vault check
aws_exec() {
  if [ -z "${AWS_VAULT:-}" ]; then
    aws-vault exec devops -- "$@"
  else
    "$@"
  fi
}

# Find Latest Golden Image
AMI_INFO=$(aws_exec aws ec2 describe-images \
  --owners self \
  --filters "Name=tag:Role,Values=meta-golden-image" "Name=state,Values=available" \
  --query "sort_by(Images, &CreationDate)[-1].{ID:ImageId,Name:Name}" \
  --output json)

AMI_ID=$(echo $AMI_INFO | jq -r '.ID // empty')
AMI_NAME=$(echo $AMI_INFO | jq -r '.Name // empty')

if [ -n "$AMI_ID" ]; then
  echo -e "  ${GREEN}✓${NC} 최신 골든 이미지를 확인했습니다: ${GREEN}${AMI_NAME}${NC} (${AMI_ID})"
else
  echo -e "  ${YELLOW}!${NC} 골든 이미지를 찾을 수 없습니다."
  echo -e "    표준화 정책에 따라 골든 이미지가 필요합니다."
  echo -e "    ${CYAN}Step:${NC} ${BOLD}make apply STACK=00-network${NC} 명령으로 VPC를 생성한 후,"
  echo -e "          ${BOLD}make build-ami${NC} 명령을 실행하여 이미지를 생성해 주세요."
fi
