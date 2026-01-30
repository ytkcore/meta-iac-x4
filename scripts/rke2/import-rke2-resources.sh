#!/bin/bash
# =============================================================================
# RKE2 Resource Import Script
# Usage: cd stacks/dev/50-rke2 && ../../../scripts/rke2/import-rke2-resources.sh
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

import_resource() {
  local step="$1" name="$2" check_cmd="$3" check_arg="$4" tf_addr="$5" import_id="$6"
  
  header "$step" "Checking $name"
  
  if eval "$check_cmd" --"$check_arg" "$import_id" >/dev/null 2>&1; then
    info "Found. Importing..."
    if terraform import -var-file=../env.tfvars "$tf_addr" "$import_id" 2>/dev/null; then
      ok "Imported $name"
    else
      warn "Already in state or failed"
    fi
  else
    info "Not found in AWS. Skipping."
  fi
}

import_resource_by_id() {
  local step="$1" name="$2" resource_id="$3" tf_addr="$4"
  
  header "$step" "Checking $name"
  
  if [[ -n "$resource_id" ]] && [[ "$resource_id" != "None" ]]; then
    info "Found: $resource_id. Importing..."
    if terraform import -var-file=../env.tfvars "$tf_addr" "$resource_id" 2>/dev/null; then
      ok "Imported $name"
    else
      warn "Already in state or failed"
    fi
  else
    info "Not found in AWS. Skipping."
  fi
}

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------
ENV="${ENV:-dev}"
PROJECT="${PROJECT:-dev}"
NAME="${NAME:-dev-network}"

ROLE_NAME="${PROJECT}-${ENV}-${NAME}-rke2-nodes-role"
PROFILE_NAME="${PROJECT}-${ENV}-${NAME}-rke2-nodes-profile"
SG_NAME="${PROJECT}-${ENV}-${NAME}-rke2-nodes-sg"
NLB_NAME="${PROJECT}-${ENV}-${NAME}-rke2"
TG_9345_NAME="${PROJECT}-${ENV}-${NAME}-9345"
TG_6443_NAME="${PROJECT}-${ENV}-${NAME}-6443"
INGRESS_NLB_NAME="${PROJECT}-${ENV}-${NAME}-ingress"
TG_HTTP_NAME="${PROJECT}-${ENV}-${NAME}-http"
TG_HTTPS_NAME="${PROJECT}-${ENV}-${NAME}-https"

# -----------------------------------------------------------------------------
# Header
# -----------------------------------------------------------------------------
echo -e "\n${BOLD}RKE2 Resource Import${NC}\n"
info "Environment: ${ENV}"
info "Project: ${PROJECT}"
info "Name: ${NAME}"
echo ""
info "Internal NLB Resources:"
info "  - IAM Role: ${ROLE_NAME}"
info "  - IAM Instance Profile: ${PROFILE_NAME}"
info "  - Security Group: ${SG_NAME}"
info "  - Internal NLB: ${NLB_NAME}"
info "  - Target Group (9345): ${TG_9345_NAME}"
info "  - Target Group (6443): ${TG_6443_NAME}"
echo ""
info "Public Ingress NLB Resources:"
info "  - Ingress NLB: ${INGRESS_NLB_NAME}"
info "  - Target Group (HTTP): ${TG_HTTP_NAME}"
info "  - Target Group (HTTPS): ${TG_HTTPS_NAME}"

read -p "Continue with import? (y/N): " confirm
[[ "$confirm" != "y" && "$confirm" != "Y" ]] && { echo "Aborted."; exit 0; }

# -----------------------------------------------------------------------------
# 1. IAM Role
# -----------------------------------------------------------------------------
import_resource "1/10" "IAM Role: ${ROLE_NAME}" \
  "aws iam get-role" "role-name" \
  'module.rke2.aws_iam_role.nodes' "${ROLE_NAME}"

# -----------------------------------------------------------------------------
# 2. IAM Instance Profile
# -----------------------------------------------------------------------------
import_resource "2/10" "IAM Instance Profile: ${PROFILE_NAME}" \
  "aws iam get-instance-profile" "instance-profile-name" \
  'module.rke2.aws_iam_instance_profile.nodes' "${PROFILE_NAME}"

# -----------------------------------------------------------------------------
# 3. IAM Role Policy Attachment
# -----------------------------------------------------------------------------
header "3/10" "Checking IAM Role Policy Attachment (SSM Core)"
if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  POLICY_ARN="arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ATTACHED=$(aws iam list-attached-role-policies --role-name "${ROLE_NAME}" \
    --query "AttachedPolicies[?PolicyArn=='${POLICY_ARN}'].PolicyArn" --output text 2>/dev/null)
  if [[ -n "$ATTACHED" ]]; then
    info "Found. Importing..."
    terraform import -var-file=../env.tfvars \
      'module.rke2.aws_iam_role_policy_attachment.ssm_core' \
      "${ROLE_NAME}/${POLICY_ARN}" 2>/dev/null && ok "Imported" || warn "Already in state or failed"
  else
    info "Policy not attached. Skipping."
  fi
else
  info "Role not found. Skipping."
fi

# -----------------------------------------------------------------------------
# 4. Security Group
# -----------------------------------------------------------------------------
header "4/10" "Checking Security Group: ${SG_NAME}"
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${SG_NAME}" \
  --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
import_resource_by_id "4/10" "Security Group" "$SG_ID" 'module.rke2.aws_security_group.nodes'

# -----------------------------------------------------------------------------
# 5. Internal NLB
# -----------------------------------------------------------------------------
header "5/10" "Checking Internal NLB: ${NLB_NAME}"
NLB_ARN=$(aws elbv2 describe-load-balancers --names "${NLB_NAME}" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || echo "")
import_resource_by_id "5/10" "Internal NLB" "$NLB_ARN" 'module.rke2.aws_lb.rke2[0]'

# -----------------------------------------------------------------------------
# 6. Target Group - 9345
# -----------------------------------------------------------------------------
header "6/10" "Checking Target Group: ${TG_9345_NAME}"
TG_9345_ARN=$(aws elbv2 describe-target-groups --names "${TG_9345_NAME}" \
  --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "")
import_resource_by_id "6/10" "Target Group 9345" "$TG_9345_ARN" 'module.rke2.aws_lb_target_group.supervisor[0]'

# -----------------------------------------------------------------------------
# 7. Target Group - 6443
# -----------------------------------------------------------------------------
header "7/10" "Checking Target Group: ${TG_6443_NAME}"
TG_6443_ARN=$(aws elbv2 describe-target-groups --names "${TG_6443_NAME}" \
  --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "")
import_resource_by_id "7/10" "Target Group 6443" "$TG_6443_ARN" 'module.rke2.aws_lb_target_group.apiserver[0]'

# -----------------------------------------------------------------------------
# 8. Public Ingress NLB
# -----------------------------------------------------------------------------
header "8/10" "Checking Public Ingress NLB: ${INGRESS_NLB_NAME}"
INGRESS_NLB_ARN=$(aws elbv2 describe-load-balancers --names "${INGRESS_NLB_NAME}" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || echo "")
import_resource_by_id "8/10" "Ingress NLB" "$INGRESS_NLB_ARN" 'module.rke2.aws_lb.ingress[0]'

# -----------------------------------------------------------------------------
# 9. Target Group - HTTP
# -----------------------------------------------------------------------------
header "9/10" "Checking Target Group: ${TG_HTTP_NAME}"
TG_HTTP_ARN=$(aws elbv2 describe-target-groups --names "${TG_HTTP_NAME}" \
  --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "")
import_resource_by_id "9/10" "Target Group HTTP" "$TG_HTTP_ARN" 'module.rke2.aws_lb_target_group.ingress_http[0]'

# -----------------------------------------------------------------------------
# 10. Target Group - HTTPS
# -----------------------------------------------------------------------------
header "10/10" "Checking Target Group: ${TG_HTTPS_NAME}"
TG_HTTPS_ARN=$(aws elbv2 describe-target-groups --names "${TG_HTTPS_NAME}" \
  --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "")
import_resource_by_id "10/10" "Target Group HTTPS" "$TG_HTTPS_ARN" 'module.rke2.aws_lb_target_group.ingress_https[0]'

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo -e "\n${GREEN}${BOLD}Import Process Completed${NC}\n"
info "Next steps:"
info "  1. Run 'terraform plan -var-file=../env.tfvars' to verify"
info "  2. Run 'terraform apply -var-file=../env.tfvars' to apply changes"
