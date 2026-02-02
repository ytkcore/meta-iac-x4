#!/bin/bash
# scripts/common/check-ami.sh

set -e

GREEN='\e[32m'
RED='\e[31m'
YELLOW='\e[33m'
CYAN='\e[36m'
NC='\e[0m'

echo -e "${CYAN}[AMI Check]${NC} 프로젝트 전역 골든 이미지를 확인합니다..."

# Check if Packer is installed
if ! command -v packer &> /dev/null; then
  echo -e "${YELLOW}Warning:${NC} Packer가 설치되어 있지 않습니다. 빌드가 필요할 경우 설치가 선행되어야 합니다."
  # brew install packer # 필요 시 활성화
fi

# Find Latest Golden Image
AMI_INFO=$(aws-vault exec devops -- aws ec2 describe-images \
  --owners self \
  --filters "Name=tag:Role,Values=meta-golden-image" "Name=state,Values=available" \
  --query "sort_by(Images, &CreationDate)[-1].{ID:ImageId,Name:Name}" \
  --output json)

AMI_ID=$(echo $AMI_INFO | jq -r '.ID // empty')
AMI_NAME=$(echo $AMI_INFO | jq -r '.Name // empty')

if [ -n "$AMI_ID" ]; then
  echo -e "  ${GREEN}✓${NC} 최신 골든 이미지를 확인했습니다: ${GREEN}${AMI_NAME}${NC} (${AMI_ID})"
else
  echo -e "  ${RED}✗${NC} 골든 이미지를 찾을 수 없습니다."
  read -p "  새로운 골든 이미지를 지금 빌드하시겠습니까? (Y/n) " BUILD_NOW
  if [[ ! "$BUILD_NOW" =~ ^[Nn]$ ]]; then
    echo -e "${CYAN}Packer 빌드를 시작합니다... (이 작업은 약 5~10분 정도 소요될 수 있습니다)${NC}"
    aws-vault exec devops -- packer build ami/golden.pkr.hcl
  else
    echo -e "${YELLOW}Skip:${NC} 골든 이미지 빌드를 건너뜁니다. 나중에 'make packer-build'로 직접 빌드할 수 있습니다."
  fi
fi
