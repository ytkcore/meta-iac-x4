#!/bin/bash
# =============================================================================
# Destroy All Terraform Stacks + Backend Bucket
# Usage: ./destroy-all.sh <ENV> <STACK_ORDER> <BACKEND_CONFIG> <STATE_PREFIX> <BOOT_DIR>
# =============================================================================

set -uo pipefail

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
GREEN=$'\e[32m'
RED=$'\e[31m'
YELLOW=$'\e[33m'
CYAN=$'\e[36m'
BOLD=$'\e[1m'
DIM=$'\e[2m'
NC=$'\e[0m'

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------
ok()     { echo -e "  ${GREEN}✓${NC} $*"; }
fail()   { echo -e "  ${RED}✗${NC} $*"; }
warn()   { echo -e "  ${YELLOW}!${NC} $*"; }
info()   { echo -e "  ${DIM}$*${NC}"; }
header() { echo -e "\n${CYAN}${BOLD}[$1]${NC} $2"; }

get_bucket() { grep -E '^bucket' "$BACKEND_CONFIG" | sed -E 's/.*"([^"]+)".*/\1/'; }
get_region() { grep -E '^region' "$BACKEND_CONFIG" | sed -E 's/.*"([^"]+)".*/\1/'; }

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------
ENV="${1:?ENV required}"
STACK_ORDER="${2:?STACK_ORDER required}"
BACKEND_CONFIG="${3:?BACKEND_CONFIG_FILE required}"
STATE_PREFIX="${4:?STATE_KEY_PREFIX required}"
BOOT_DIR="${5:?BOOT_DIR required}"

# -----------------------------------------------------------------------------
# Confirmation
# -----------------------------------------------------------------------------
echo -e "\n${BOLD}Complete Infrastructure Teardown${NC}\n"
echo -e "${YELLOW}⚠ WARNING: This will destroy ALL stacks in reverse order and the S3 backend bucket!${NC}"
echo ""
read -p "Are you sure you want to proceed? (yes/no): " CONFIRM
[[ "$CONFIRM" != "yes" ]] && { echo "Aborted."; exit 1; }

echo ""
info "Starting complete teardown..."

# -----------------------------------------------------------------------------
# Destroy Stacks
# -----------------------------------------------------------------------------
REVERSED=$(echo "$STACK_ORDER" | tr ' ' '\n' | tail -r | tr '\n' ' ')

for STACK in $REVERSED; do
  header "Destroy" "${ENV}/${STACK}"
  STATE_KEY="${STATE_PREFIX}/${ENV}/${STACK}.tfstate"
  
  if [[ -f "$BACKEND_CONFIG" ]]; then
    STATE_BUCKET=$(get_bucket)
    if aws s3api head-object --bucket "$STATE_BUCKET" --key "$STATE_KEY" >/dev/null 2>&1; then
      if make destroy ENV="$ENV" STACK="$STACK" TF_OPTS="-auto-approve" 2>&1; then
        ok "Destroyed $STACK"
      else
        fail "Failed to destroy $STACK, continuing..."
      fi
    else
      info "Stack $STACK has no state, skipping..."
    fi
  else
    if make destroy ENV="$ENV" STACK="$STACK" TF_OPTS="-auto-approve" 2>&1; then
      ok "Destroyed $STACK"
    else
      info "Stack $STACK may not exist, skipping..."
    fi
  fi
done

# -----------------------------------------------------------------------------
# Cleanup AWS Resources Created Outside Terraform
# (ExternalDNS records, K8s-provisioned ELBs, orphaned ENIs)
# -----------------------------------------------------------------------------
header "Cleanup" "AWS resources created by K8s controllers"

# 1. Delete ELBs in the VPC (created by K8s LoadBalancer services)
cleanup_elbs() {
  local vpc_id="$1"
  if [[ -z "$vpc_id" ]]; then return; fi
  
  info "Checking for Load Balancers in VPC $vpc_id..."
  local elb_arns=$(aws elbv2 describe-load-balancers \
    --query "LoadBalancers[?VpcId=='$vpc_id'].LoadBalancerArn" \
    --output text 2>/dev/null)
  
  for arn in $elb_arns; do
    if [[ -n "$arn" && "$arn" != "None" ]]; then
      info "Deleting ELB: $arn"
      aws elbv2 delete-load-balancer --load-balancer-arn "$arn" 2>/dev/null && \
        ok "Deleted ELB" || warn "Failed to delete ELB"
    fi
  done
  
  # Wait for ENIs to be released (ELB deletion is async)
  if [[ -n "$elb_arns" && "$elb_arns" != "None" ]]; then
    info "Waiting 30s for ELB ENIs to be released..."
    sleep 30
  fi
}

# 2. Delete orphaned ENIs (network interfaces not attached to instances)
cleanup_enis() {
  local vpc_id="$1"
  if [[ -z "$vpc_id" ]]; then return; fi
  
  info "Checking for orphaned ENIs in VPC $vpc_id..."
  local eni_ids=$(aws ec2 describe-network-interfaces \
    --filters "Name=vpc-id,Values=$vpc_id" "Name=status,Values=available" \
    --query "NetworkInterfaces[].NetworkInterfaceId" \
    --output text 2>/dev/null)
  
  for eni in $eni_ids; do
    if [[ -n "$eni" && "$eni" != "None" ]]; then
      info "Deleting orphaned ENI: $eni"
      aws ec2 delete-network-interface --network-interface-id "$eni" 2>/dev/null && \
        ok "Deleted ENI $eni" || warn "Failed to delete ENI $eni"
    fi
  done
}

# 3. Delete Route53 records created by ExternalDNS (in private zone)
cleanup_route53_records() {
  local zone_id="$1"
  local domain="$2"
  if [[ -z "$zone_id" ]]; then return; fi
  
  info "Checking for ExternalDNS records in zone $zone_id..."
  
  # Get all non-NS/SOA records that were created by external-dns
  local records_json=$(aws route53 list-resource-record-sets \
    --hosted-zone-id "$zone_id" \
    --query "ResourceRecordSets[?Type!='NS' && Type!='SOA']" \
    --output json 2>/dev/null)
  
  if [[ "$records_json" == "[]" || -z "$records_json" ]]; then
    info "No custom DNS records found"
    return
  fi
  
  # Build batch delete request
  local change_batch=$(echo "$records_json" | jq -c '{Changes: [.[] | {Action: "DELETE", ResourceRecordSet: .}]}')
  
  if [[ -n "$change_batch" && "$change_batch" != '{"Changes":[]}' ]]; then
    info "Deleting ExternalDNS records..."
    echo "$change_batch" > /tmp/dns-cleanup-batch.json
    aws route53 change-resource-record-sets \
      --hosted-zone-id "$zone_id" \
      --change-batch file:///tmp/dns-cleanup-batch.json 2>/dev/null && \
      ok "Deleted DNS records" || warn "Failed to delete some DNS records"
    rm -f /tmp/dns-cleanup-batch.json
  fi
}

# Get VPC ID from network state (before it's destroyed)
VPC_ID=""
ZONE_ID=""
if [[ -f "$BACKEND_CONFIG" ]]; then
  STATE_BUCKET=$(get_bucket)
  STATE_REGION=$(get_region)
  NETWORK_KEY="${STATE_PREFIX}/${ENV}/00-network.tfstate"
  
  # Try to extract VPC ID from state
  if aws s3api head-object --bucket "$STATE_BUCKET" --key "$NETWORK_KEY" >/dev/null 2>&1; then
    STATE_JSON=$(aws s3 cp "s3://$STATE_BUCKET/$NETWORK_KEY" - 2>/dev/null)
    VPC_ID=$(echo "$STATE_JSON" | jq -r '.outputs.vpc_id.value // empty' 2>/dev/null)
    ZONE_ID=$(echo "$STATE_JSON" | jq -r '.outputs.route53_zone_id.value // empty' 2>/dev/null)
  fi
  
  # Fallback: try to find VPC by tag
  if [[ -z "$VPC_ID" ]]; then
    VPC_ID=$(aws ec2 describe-vpcs \
      --filters "Name=tag:Project,Values=*" "Name=tag:Environment,Values=$ENV" \
      --query "Vpcs[0].VpcId" --output text 2>/dev/null)
    [[ "$VPC_ID" == "None" ]] && VPC_ID=""
  fi
fi

if [[ -n "$VPC_ID" ]]; then
  info "Found VPC: $VPC_ID"
  cleanup_elbs "$VPC_ID"
  cleanup_enis "$VPC_ID"
fi

if [[ -n "$ZONE_ID" ]]; then
  info "Found Route53 Zone: $ZONE_ID"
  cleanup_route53_records "$ZONE_ID"
fi

# -----------------------------------------------------------------------------
# Destroy Backend
# -----------------------------------------------------------------------------
header "Final" "Destroying S3 Backend Bucket"

if [[ -f "$BACKEND_CONFIG" ]]; then
  STATE_BUCKET=$(get_bucket)
  STATE_REGION=$(get_region)
  
  info "Bucket: $STATE_BUCKET ($STATE_REGION)"
  info "Destroying backend infrastructure (force_destroy=true handles cleanup)..."
  
  (cd "$BOOT_DIR" && \
   terraform init -upgrade=false -reconfigure >/dev/null 2>&1 && \
   terraform destroy -auto-approve \
     -var="state_bucket=$STATE_BUCKET" \
     -var="state_region=$STATE_REGION")
  
  ok "Backend bucket destroyed: s3://$STATE_BUCKET"
else
  warn "Backend config not found, skipping bucket cleanup."
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo -e "\n${GREEN}${BOLD}Complete teardown finished!${NC}"
info "Environment $ENV has been completely removed."
