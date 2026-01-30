#!/bin/bash
# =============================================================================
# RKE2 Resources Force Cleanup Script
# Usage: aws-vault exec <profile> -- ./cleanup-rke2-resources.sh <vpc_id> <cluster_name_prefix>
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

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------
VPC_ID="${1:-}"
NAME_PREFIX="${2:-}"

if [[ -z "$VPC_ID" ]] || [[ -z "$NAME_PREFIX" ]]; then
  echo "Usage: $0 <vpc_id> <cluster_name_prefix>"
  echo "Example: $0 vpc-xxxx dev-dev-dev-network"
  exit 1
fi

# -----------------------------------------------------------------------------
# Confirmation
# -----------------------------------------------------------------------------
echo -e "\n${BOLD}RKE2 Force Cleanup${NC} - ${NAME_PREFIX} (VPC: $VPC_ID)\n"
echo -e "${YELLOW}⚠ WARNING: This will DELETE all resources related to '$NAME_PREFIX'${NC}"
read -p "Press [Enter] to continue or [Ctrl+C] to abort..."

# -----------------------------------------------------------------------------
# 1. Load Balancers
# -----------------------------------------------------------------------------
header 1 "Cleaning Load Balancers"

# Classic ELB
ELBS=$(aws elb describe-load-balancers --query "LoadBalancerDescriptions[?VPCId=='$VPC_ID'].LoadBalancerName" --output text)
if [[ "$ELBS" != "None" ]] && [[ -n "$ELBS" ]]; then
  for lb in $ELBS; do
    IS_TARGET=false
    [[ "$lb" == "$NAME_PREFIX"* ]] && IS_TARGET=true
    
    IS_K8S=$(aws elb describe-tags --load-balancer-names "$lb" --query "TagDescriptions[0].Tags[?starts_with(Key, 'kubernetes.io/cluster/')]" --output text)
    [[ -n "$IS_K8S" ]] && [[ "$IS_K8S" != "None" ]] && IS_TARGET=true

    if [[ "$IS_TARGET" == "true" ]]; then
      info "Deleting Classic ELB: $lb"
      aws elb delete-load-balancer --load-balancer-name "$lb" || warn "Error deleting $lb"
    fi
  done
fi

# NLB/ALB (v2)
LB_ARNS=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" --output text)
if [[ "$LB_ARNS" != "None" ]] && [[ -n "$LB_ARNS" ]]; then
  for lb_arn in $LB_ARNS; do
    LB_NAME=$(aws elbv2 describe-load-balancers --load-balancer-arns "$lb_arn" --query "LoadBalancers[0].LoadBalancerName" --output text)
    IS_TARGET=false
    
    [[ "$LB_NAME" == "$NAME_PREFIX"* ]] && IS_TARGET=true
    
    IS_K8S=$(aws elbv2 describe-tags --resource-arns "$lb_arn" --query "TagDescriptions[0].Tags[?starts_with(Key, 'kubernetes.io/cluster/')]" --output text)
    [[ -n "$IS_K8S" ]] && [[ "$IS_K8S" != "None" ]] && IS_TARGET=true

    if [[ "$IS_TARGET" == "true" ]]; then
      info "Deleting NLB/ALB: $LB_NAME"
      aws elbv2 modify-load-balancer-attributes --load-balancer-arn "$lb_arn" --attributes Key=deletion_protection.enabled,Value=false 2>/dev/null
      aws elbv2 delete-load-balancer --load-balancer-arn "$lb_arn" || warn "Error deleting $LB_NAME"
    fi
  done
fi
ok "Load balancers cleaned"

# -----------------------------------------------------------------------------
# 2. Target Groups
# -----------------------------------------------------------------------------
header 2 "Cleaning Target Groups"
TG_ARNS=$(aws elbv2 describe-target-groups --query "TargetGroups[?VpcId=='$VPC_ID'].TargetGroupArn" --output text)
if [[ "$TG_ARNS" != "None" ]] && [[ -n "$TG_ARNS" ]]; then
  for tg_arn in $TG_ARNS; do
    TG_NAME=$(aws elbv2 describe-target-groups --target-group-arns "$tg_arn" --query "TargetGroups[0].TargetGroupName" --output text)
    if [[ "$TG_NAME" == "$NAME_PREFIX"* ]]; then
      info "Deleting Target Group: $TG_NAME"
      aws elbv2 delete-target-group --target-group-arn "$tg_arn" || warn "Error deleting $TG_NAME"
    fi
  done
fi
ok "Target groups cleaned"

# -----------------------------------------------------------------------------
# 3. EC2 Instances
# -----------------------------------------------------------------------------
header 3 "Terminating EC2 Instances"
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$NAME_PREFIX-*" "Name=instance-state-name,Values=running,stopped,stopping,pending" \
  --query "Reservations[].Instances[].InstanceId" --output text)

if [[ -n "$INSTANCE_IDS" ]] && [[ "$INSTANCE_IDS" != "None" ]]; then
  info "Terminating: $INSTANCE_IDS"
  aws ec2 terminate-instances --instance-ids $INSTANCE_IDS --no-cli-pager > /dev/null
  info "Waiting for termination..."
  aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS
  ok "Instances terminated"
else
  info "No active instances found"
fi

# -----------------------------------------------------------------------------
# 4. EBS Volumes
# -----------------------------------------------------------------------------
header 4 "Cleaning Ghost EBS Volumes"
VOLUMES_BY_TAG=$(aws ec2 describe-volumes --filters "Name=tag-key,Values=kubernetes.io/cluster/${NAME_PREFIX}*" "Name=status,Values=available" --query "Volumes[].VolumeId" --output text)
VOLUMES_BY_NAME=$(aws ec2 describe-volumes --filters "Name=tag:Name,Values=$NAME_PREFIX-*" "Name=status,Values=available" --query "Volumes[].VolumeId" --output text)
ALL_VOLUMES=$(echo "$VOLUMES_BY_TAG $VOLUMES_BY_NAME" | tr ' ' '\n' | sort -u | tr '\n' ' ')

if [[ -n "$ALL_VOLUMES" ]] && [[ "$ALL_VOLUMES" != " " ]]; then
  for vol in $ALL_VOLUMES; do
    [[ -n "$vol" ]] && [[ "$vol" != "None" ]] && {
      info "Deleting EBS Volume: $vol"
      aws ec2 delete-volume --volume-id "$vol" || warn "Error deleting volume $vol"
    }
  done
  ok "Volumes cleaned"
else
  info "No leftover EBS volumes found"
fi

# -----------------------------------------------------------------------------
# 5. Security Groups
# -----------------------------------------------------------------------------
header 5 "Cleaning Security Groups"
SG_IDS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=$NAME_PREFIX-*" --query "SecurityGroups[].GroupId" --output text)

if [[ "$SG_IDS" != "None" ]] && [[ -n "$SG_IDS" ]]; then
  for sg_id in $SG_IDS; do
    info "Deleting SG: $sg_id"
    for i in {1..3}; do
      aws ec2 delete-security-group --group-id "$sg_id" 2>/dev/null && break
      sleep 2
    done
  done
  ok "Security groups cleaned"
fi

# -----------------------------------------------------------------------------
# 6. IAM Roles & Profiles
# -----------------------------------------------------------------------------
header 6 "Cleaning IAM Roles & Profiles"
PROFILE_NAME="${NAME_PREFIX}-rke2-nodes-profile"
ROLE_NAME="${NAME_PREFIX}-rke2-nodes-role"

if aws iam get-instance-profile --instance-profile-name "$PROFILE_NAME" >/dev/null 2>&1; then
  info "Deleting Instance Profile: $PROFILE_NAME"
  aws iam remove-role-from-instance-profile --instance-profile-name "$PROFILE_NAME" --role-name "$ROLE_NAME" 2>/dev/null
  aws iam delete-instance-profile --instance-profile-name "$PROFILE_NAME"
fi

if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  info "Deleting Role: $ROLE_NAME"
  aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" 2>/dev/null
  aws iam delete-role --role-name "$ROLE_NAME"
fi
ok "IAM resources cleaned"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo -e "\n${GREEN}${BOLD}Force Cleanup Finished${NC}"
info "You can now run 'terraform apply' or 'terraform destroy'"