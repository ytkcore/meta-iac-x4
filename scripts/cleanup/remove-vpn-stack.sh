#!/bin/bash
# scripts/cleanup/remove-vpn-stack.sh
#
# Client VPN 스택의 모든 리소스를 수동으로 정리하는 스크립트
# 사용법: aws-vault exec devops -- ./scripts/cleanup/remove-vpn-stack.sh [ENV] [PROJECT] [--force]
#
# 보안 강화:
# - 입력 검증
# - 삭제 전 확인
# - 정확한 리소스 타겟팅
# - 감사 로그 기록

set -euo pipefail  # 개선: -u (미정의 변수 에러), -o pipefail (파이프 에러 전파)

# =============================================================================
# 입력 검증
# =============================================================================

ENV=${1:-}
PROJECT=${2:-}
FORCE_MODE=false

# 플래그 파싱
for arg in "$@"; do
  if [ "$arg" == "--force" ]; then
    FORCE_MODE=true
  fi
done

# 입력 검증: ENV
if [ -z "$ENV" ]; then
  echo "Error: Environment (ENV) is required"
  echo "Usage: $0 <ENV> <PROJECT> [--force]"
  echo "Example: $0 dev meta"
  exit 1
fi

# 입력 검증: 허용된 ENV만 허용 (화이트리스트)
if [[ ! "$ENV" =~ ^(dev|staging|prod)$ ]]; then
  echo "Error: Invalid environment '$ENV'. Allowed: dev, staging, prod"
  exit 1
fi

# 입력 검증: PROJECT
if [ -z "$PROJECT" ]; then
  echo "Error: Project name is required"
  echo "Usage: $0 <ENV> <PROJECT> [--force]"
  exit 1
fi

# 입력 검증: PROJECT 안전성 체크 (알파벳, 숫자, 하이픈만 허용)
if [[ ! "$PROJECT" =~ ^[a-zA-Z0-9-]+$ ]]; then
  echo "Error: Invalid project name '$PROJECT'. Only alphanumeric and hyphens allowed."
  exit 1
fi

# =============================================================================
# 감사 로그 설정
# =============================================================================

LOG_DIR="logs/cleanup"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/vpn-cleanup-$(date +%Y%m%d-%H%M%S).log"

log() {
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] $*" | tee -a "$LOG_FILE"
}

log "==================================="
log "VPN Cleanup Script Started"
log "User: $(whoami)"
log "Environment: $ENV"
log "Project: $PROJECT"
log "Force Mode: $FORCE_MODE"
log "AWS Caller Identity: $(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null || echo 'Unknown')"
log "==================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}================================================================================"
echo "Client VPN Stack Cleanup Script (Security Enhanced)"
echo "Environment: $ENV | Project: $PROJECT"
echo "Log file: $LOG_FILE"
echo -e "================================================================================${NC}\n"

# =============================================================================
# AWS 권한 확인
# =============================================================================

echo -e "${YELLOW}Pre-flight: Checking AWS credentials and permissions...${NC}"

if ! aws sts get-caller-identity &>/dev/null; then
  echo -e "${RED}Error: AWS credentials not configured or expired${NC}"
  log "ERROR: AWS credentials check failed"
  exit 1
fi

CALLER_ARN=$(aws sts get-caller-identity --query 'Arn' --output text)
echo -e "${GREEN}✓ AWS Identity: $CALLER_ARN${NC}\n"
log "AWS Identity verified: $CALLER_ARN"

# =============================================================================
# 리소스 검색 (정확한 타겟팅)
# =============================================================================

echo -e "${YELLOW}Step 1: Finding VPN Endpoint...${NC}"

# 정확한 태그 매칭 (보안 개선)
VPN_NAME_TAG="$ENV-$PROJECT-client-vpn"
VPN_ENDPOINT_ID=$(aws ec2 describe-client-vpn-endpoints \
  --query "ClientVpnEndpoints[?Tags[?Key=='Name'&&Value=='$VPN_NAME_TAG']].ClientVpnEndpointId" \
  --output text 2>/dev/null || echo "")

if [ -z "$VPN_ENDPOINT_ID" ] || [ "$VPN_ENDPOINT_ID" == "None" ]; then
  echo -e "${GREEN}✓ No VPN Endpoint found with exact name: $VPN_NAME_TAG${NC}"
  log "INFO: No VPN Endpoint found. Exiting cleanly."
  exit 0
fi

echo -e "${GREEN}✓ Found VPN Endpoint: $VPN_ENDPOINT_ID${NC}"
log "FOUND: VPN Endpoint: $VPN_ENDPOINT_ID"

# VPN Endpoint 상세 정보 조회 (검증용)
VPN_DETAILS=$(aws ec2 describe-client-vpn-endpoints \
  --client-vpn-endpoint-ids "$VPN_ENDPOINT_ID" \
  --query 'ClientVpnEndpoints[0].[DnsName,Status.Code,ClientCidrBlock]' \
  --output json)

echo -e "  DNS Name: $(echo "$VPN_DETAILS" | jq -r '.[0]')"
echo -e "  Status: $(echo "$VPN_DETAILS" | jq -r '.[1]')"
echo -e "  CIDR: $(echo "$VPN_DETAILS" | jq -r '.[2]')\n"

# =============================================================================
# 삭제 대상 리소스 목록 수집
# =============================================================================

echo -e "${YELLOW}Collecting resources to delete...${NC}\n"

# Network Associations
ASSOC_ID=$(aws ec2 describe-client-vpn-target-networks \
  --client-vpn-endpoint-id "$VPN_ENDPOINT_ID" \
  --query 'ClientVpnTargetNetworks[0].AssociationId' \
  --output text 2>/dev/null || echo "")

# Security Group (정확한 태그 매칭)
SG_NAME_TAG="$ENV-$PROJECT-vpn-endpoint-sg"
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=$SG_NAME_TAG" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null || echo "")

# ACM Certificates (정확한 도메인 매칭으로 개선)
# 보안 개선: 정확한 패턴만 매칭
CERT_ARNS=$(aws acm list-certificates \
  --query "CertificateSummaryList[?DomainName=='vpn-server.$ENV.unifiedmeta.net' || DomainName=='vpn-client.$ENV.unifiedmeta.net'].CertificateArn" \
  --output text 2>/dev/null || echo "")

# CloudWatch Log Group (정확한 prefix)
LOG_GROUP=$(aws logs describe-log-groups \
  --log-group-name-prefix "$ENV-$PROJECT-vpn" \
  --query 'logGroups[0].logGroupName' \
  --output text 2>/dev/null || echo "")

# =============================================================================
# 삭제 대상 요약 및 확인
# =============================================================================

echo -e "${CYAN}================================================================================"
echo "Resources to be deleted:"
echo -e "================================================================================${NC}"
echo -e "VPN Endpoint:       ${YELLOW}${VPN_ENDPOINT_ID}${NC}"
echo -e "Network Assoc:      ${YELLOW}${ASSOC_ID:-None}${NC}"
echo -e "Security Group:     ${YELLOW}${SG_ID:-None}${NC}"
echo -e "ACM Certificates:   ${YELLOW}${CERT_ARNS:-None}${NC}"
echo -e "CloudWatch Logs:    ${YELLOW}${LOG_GROUP:-None}${NC}"
echo -e "${CYAN}================================================================================${NC}\n"

log "DELETE TARGETS:"
log "  - VPN Endpoint: $VPN_ENDPOINT_ID"
log "  - Network Association: ${ASSOC_ID:-None}"
log "  - Security Group: ${SG_ID:-None}"
log "  - ACM Certificates: ${CERT_ARNS:-None}"
log "  - CloudWatch Logs: ${LOG_GROUP:-None}"

# =============================================================================
# 사용자 확인 (보안 개선)
# =============================================================================

if [ "$FORCE_MODE" != "true" ]; then
  echo -e "${RED}WARNING: This will permanently delete the above resources!${NC}"
  echo -e "${YELLOW}Type 'DELETE' to confirm, or anything else to cancel:${NC} "
  read -r CONFIRMATION
  
  if [ "$CONFIRMATION" != "DELETE" ]; then
    echo -e "${GREEN}Cancelled by user.${NC}"
    log "INFO: Cleanup cancelled by user"
    exit 0
  fi
  log "INFO: User confirmed deletion"
else
  log "INFO: Force mode enabled, skipping confirmation"
fi

echo ""

# =============================================================================
# 리소스 삭제 시작
# =============================================================================

# Authorization Rule 삭제
echo -e "${YELLOW}Step 2: Revoking authorization rules...${NC}"
if aws ec2 revoke-client-vpn-ingress \
  --client-vpn-endpoint-id "$VPN_ENDPOINT_ID" \
  --target-network-cidr 10.0.0.0/16 \
  --revoke-all-groups 2>/dev/null; then
  echo -e "${GREEN}✓ Authorization rules revoked${NC}\n"
  log "SUCCESS: Authorization rules revoked"
else
  echo -e "${YELLOW}  (No authorization rules to revoke)${NC}\n"
  log "INFO: No authorization rules found"
fi

# Network Association 삭제
if [ -n "$ASSOC_ID" ] && [ "$ASSOC_ID" != "None" ]; then
  echo -e "${YELLOW}Step 3: Disassociating network...${NC}"
  echo -e "  Association ID: ${CYAN}$ASSOC_ID${NC}"
  
  if aws ec2 disassociate-client-vpn-target-network \
    --client-vpn-endpoint-id "$VPN_ENDPOINT_ID" \
    --association-id "$ASSOC_ID"; then
    log "SUCCESS: Network disassociation initiated: $ASSOC_ID"
  else
    log "ERROR: Failed to disassociate network: $ASSOC_ID"
    exit 1
  fi
  
  echo -e "${YELLOW}  Waiting for disassociation to complete (this may take 2-5 minutes)...${NC}"
  
  # 삭제 완료 대기 (최대 10분)
  MAX_WAIT=60  # 10분 (60 * 10초)
  COUNT=0
  while [ $COUNT -lt $MAX_WAIT ]; do
    REMAINING=$(aws ec2 describe-client-vpn-target-networks \
      --client-vpn-endpoint-id "$VPN_ENDPOINT_ID" \
      --query 'length(ClientVpnTargetNetworks)' \
      --output text 2>/dev/null || echo "0")
    
    if [ "$REMAINING" == "0" ]; then
      echo -e "${GREEN}✓ Network disassociation completed${NC}\n"
      log "SUCCESS: Network disassociation completed"
      break
    fi
    
    STATUS=$(aws ec2 describe-client-vpn-target-networks \
      --client-vpn-endpoint-id "$VPN_ENDPOINT_ID" \
      --query 'ClientVpnTargetNetworks[0].Status.Code' \
      --output text 2>/dev/null || echo "unknown")
    
    echo -e "  Status: ${YELLOW}$STATUS${NC} (waiting... $COUNT/60)"
    sleep 10
    COUNT=$((COUNT + 1))
  done
  
  if [ $COUNT -ge $MAX_WAIT ]; then
    echo -e "${RED}⚠ Timeout waiting for disassociation. Please check AWS Console.${NC}"
    log "ERROR: Timeout waiting for network disassociation"
    exit 1
  fi
else
  echo -e "${GREEN}✓ No network associations found${NC}\n"
  log "INFO: No network associations to delete"
fi

# VPN Endpoint 삭제
echo -e "${YELLOW}Step 4: Deleting VPN Endpoint...${NC}"
if aws ec2 delete-client-vpn-endpoint --client-vpn-endpoint-id "$VPN_ENDPOINT_ID"; then
  log "SUCCESS: VPN Endpoint deletion initiated: $VPN_ENDPOINT_ID"
else
  log "ERROR: Failed to delete VPN Endpoint: $VPN_ENDPOINT_ID"
  exit 1
fi

echo -e "${YELLOW}  Waiting for VPN Endpoint deletion (30-60 seconds)...${NC}"
sleep 30

# 삭제 확인
MAX_WAIT=12  # 2분 (12 * 10초)
COUNT=0
while [ $COUNT -lt $MAX_WAIT ]; do
  if ! aws ec2 describe-client-vpn-endpoints \
      --client-vpn-endpoint-ids "$VPN_ENDPOINT_ID" \
      --output text >/dev/null 2>&1; then
    echo -e "${GREEN}✓ VPN Endpoint deleted${NC}\n"
    log "SUCCESS: VPN Endpoint deleted: $VPN_ENDPOINT_ID"
    break
  fi
  echo -e "  Still deleting... ($COUNT/12)"
  sleep 10
  COUNT=$((COUNT + 1))
done

# Security Group 삭제
if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
  echo -e "${YELLOW}Step 5: Deleting Security Group...${NC}"
  echo -e "  Security Group ID: ${CYAN}$SG_ID${NC}"
  if aws ec2 delete-security-group --group-id "$SG_ID"; then
    echo -e "${GREEN}✓ Security Group deleted${NC}\n"
    log "SUCCESS: Security Group deleted: $SG_ID"
  else
    echo -e "${RED}⚠ Failed to delete Security Group${NC}\n"
    log "ERROR: Failed to delete Security Group: $SG_ID"
  fi
else
  echo -e "${GREEN}✓ No Security Group found${NC}\n"
  log "INFO: No Security Group to delete"
fi

# ACM Certificates 삭제
if [ -n "$CERT_ARNS" ] && [ "$CERT_ARNS" != "None" ]; then
  echo -e "${YELLOW}Step 6: Deleting ACM Certificates...${NC}"
  CERT_COUNT=0
  echo "$CERT_ARNS" | tr '\t' '\n' | while read -r cert_arn; do
    if [ -n "$cert_arn" ]; then
      echo -e "  Deleting: ${CYAN}$cert_arn${NC}"
      if aws acm delete-certificate --certificate-arn "$cert_arn"; then
        log "SUCCESS: ACM Certificate deleted: $cert_arn"
        CERT_COUNT=$((CERT_COUNT + 1))
      else
        log "ERROR: Failed to delete ACM Certificate: $cert_arn"
      fi
    fi
  done
  echo -e "${GREEN}✓ Certificate deletion completed${NC}\n"
else
  echo -e "${GREEN}✓ No ACM Certificates found${NC}\n"
  log "INFO: No ACM Certificates to delete"
fi

# CloudWatch Log Group 삭제
if [ -n "$LOG_GROUP" ] && [ "$LOG_GROUP" != "None" ]; then
  echo -e "${YELLOW}Step 7: Deleting CloudWatch Log Group...${NC}"
  echo -e "  Log Group: ${CYAN}$LOG_GROUP${NC}"
  if aws logs delete-log-group --log-group-name "$LOG_GROUP"; then
    echo -e "${GREEN}✓ CloudWatch Log Group deleted${NC}\n"
    log "SUCCESS: CloudWatch Log Group deleted: $LOG_GROUP"
  else
    echo -e "${RED}⚠ Failed to delete Log Group${NC}\n"
    log "ERROR: Failed to delete CloudWatch Log Group: $LOG_GROUP"
  fi
else
  echo -e "${GREEN}✓ No CloudWatch Log Groups found${NC}\n"
  log "INFO: No CloudWatch Log Groups to delete"
fi

# =============================================================================
# 최종 검증
# =============================================================================

echo -e "${CYAN}================================================================================"
echo "Final Verification"
echo -e "================================================================================${NC}\n"

echo -e "${YELLOW}Checking remaining VPN resources...${NC}"

VPN_CHECK=$(aws ec2 describe-client-vpn-endpoints \
  --query "ClientVpnEndpoints[?Tags[?Key=='Name'&&Value=='$VPN_NAME_TAG']].ClientVpnEndpointId" \
  --output text 2>/dev/null || echo "")

SG_CHECK=$(aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=$SG_NAME_TAG" \
  --query 'SecurityGroups[*].GroupId' \
  --output text 2>/dev/null || echo "")

if [ -z "$VPN_CHECK" ] && [ -z "$SG_CHECK" ]; then
  echo -e "${GREEN}✅ All VPN resources successfully removed!${NC}"
  log "SUCCESS: All VPN resources verified as deleted"
else
  echo -e "${RED}⚠ Some resources may still exist. Please check manually:${NC}"
  [ -n "$VPN_CHECK" ] && echo -e "  VPN Endpoints: ${YELLOW}$VPN_CHECK${NC}"
  [ -n "$SG_CHECK" ] && echo -e "  Security Groups: ${YELLOW}$SG_CHECK${NC}"
  log "WARNING: Some resources may still exist - VPN: $VPN_CHECK, SG: $SG_CHECK"
fi

echo -e "\n${CYAN}================================================================================${NC}"
echo -e "${GREEN}Cleanup completed!${NC}"
echo -e "Log file: ${CYAN}$LOG_FILE${NC}"
echo -e "${CYAN}================================================================================${NC}"

log "==================================="
log "VPN Cleanup Script Completed"
log "==================================="
