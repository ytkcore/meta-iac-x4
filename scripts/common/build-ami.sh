#!/bin/bash
# scripts/common/build-ami.sh

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

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV="${ENV:-dev}"

aws_exec() {
  if [ -z "${AWS_VAULT:-}" ]; then
    aws-vault exec devops -- "$@"
  else
    "$@"
  fi
}

echo -e "${CYAN}[AMI Build]${NC} 빌드 환경 및 기존 AMI를 확인합니다..."

# 0. Check if AMI already exists
AMI_INFO=$(aws_exec aws ec2 describe-images \
  --owners self \
  --filters "Name=tag:Role,Values=meta-golden-image" "Name=state,Values=available" \
  --query "sort_by(Images, &CreationDate)[-1].ImageId" --output text)

if [ "$AMI_INFO" != "None" ] && [ -n "$AMI_INFO" ]; then
  echo -e "  ${GREEN}✓${NC} 유효한 골든 이미지가 이미 존재합니다: ${GREEN}${AMI_INFO}${NC}"
  echo -e "    빌드를 건너뜁니다."
  exit 0
fi

# 1. VPC & Subnet Lookup
# We look for the public subnet in the dev-meta VPC
VPC_INFO=$(aws_exec aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=*${ENV}-meta-vpc*" "Name=state,Values=available" \
  --query "Vpcs[0].VpcId" --output text)

if [ "$VPC_INFO" == "None" ] || [ -z "$VPC_INFO" ]; then
  echo -e "  ${RED}✗${NC} 활성화된 VPC를 찾을 수 없습니다. '${BOLD}make apply STACK=00-network${NC}'를 먼저 실행해 주세요."
  exit 1
fi

# Find a public subnet in that VPC
SUBNET_ID=$(aws_exec aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_INFO}" "Name=tag:Tier,Values=public" \
  --query "Subnets[0].SubnetId" --output text)

if [ "$SUBNET_ID" == "None" ] || [ -z "$SUBNET_ID" ]; then
  echo -e "  ${RED}✗${NC} 퍼블릭 서브넷을 찾을 수 없습니다."
  exit 1
fi

echo -e "  ${GREEN}✓${NC} 빌드 환경 확인: VPC=${VPC_INFO}, Subnet=${SUBNET_ID}"

# 2. Packer Process
echo -e "${CYAN}Packer 플러그인을 초기화합니다...${NC}"
aws_exec packer init "${ROOT_DIR}/ami/golden.pkr.hcl"

echo -e "${CYAN}Packer 빌드를 시작합니다... (이 작업은 약 5~10분 정도 소요될 수 있습니다)${NC}"
aws_exec packer build \
  -var "vpc_id=${VPC_INFO}" \
  -var "subnet_id=${SUBNET_ID}" \
  "${ROOT_DIR}/ami/golden.pkr.hcl"
