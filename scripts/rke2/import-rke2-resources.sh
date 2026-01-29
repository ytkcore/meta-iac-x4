#!/bin/bash
###############################################################################
# import-rke2-resources.sh
#
# 기존에 AWS에 생성되어 있지만 Terraform state에 없는 RKE2 리소스들을
# Terraform state로 import하는 스크립트입니다.
#
# 사용법:
#   cd stacks/dev/50-rke2
#   ../../../scripts/import-rke2-resources.sh
#
# 또는 환경을 지정:
#   ENV=prod ../../../scripts/import-rke2-resources.sh
###############################################################################
set -e

# 환경 변수 (기본값: dev)
ENV="${ENV:-dev}"
PROJECT="${PROJECT:-dev}"
NAME="${NAME:-dev-network}"

# 리소스 이름 패턴 (modules/rke2-cluster/main.tf 참조)
ROLE_NAME="${PROJECT}-${ENV}-${NAME}-rke2-nodes-role"
PROFILE_NAME="${PROJECT}-${ENV}-${NAME}-rke2-nodes-profile"
SG_NAME="${PROJECT}-${ENV}-${NAME}-rke2-nodes-sg"
NLB_NAME="${PROJECT}-${ENV}-${NAME}-rke2"
TG_9345_NAME="${PROJECT}-${ENV}-${NAME}-9345"
TG_6443_NAME="${PROJECT}-${ENV}-${NAME}-6443"

# Public Ingress NLB 리소스 이름
INGRESS_NLB_NAME="${PROJECT}-${ENV}-${NAME}-ingress"
TG_HTTP_NAME="${PROJECT}-${ENV}-${NAME}-http"
TG_HTTPS_NAME="${PROJECT}-${ENV}-${NAME}-https"

echo "=============================================="
echo "RKE2 Resource Import Script"
echo "=============================================="
echo "Environment: ${ENV}"
echo "Project: ${PROJECT}"
echo "Name: ${NAME}"
echo ""
echo "Internal NLB Resources:"
echo "  - IAM Role: ${ROLE_NAME}"
echo "  - IAM Instance Profile: ${PROFILE_NAME}"
echo "  - Security Group: ${SG_NAME}"
echo "  - Internal NLB: ${NLB_NAME}"
echo "  - Target Group (9345): ${TG_9345_NAME}"
echo "  - Target Group (6443): ${TG_6443_NAME}"
echo ""
echo "Public Ingress NLB Resources:"
echo "  - Ingress NLB: ${INGRESS_NLB_NAME}"
echo "  - Target Group (HTTP): ${TG_HTTP_NAME}"
echo "  - Target Group (HTTPS): ${TG_HTTPS_NAME}"
echo "=============================================="
echo ""

# 확인
read -p "Continue with import? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "=== Starting import process ==="
echo ""

# 1. IAM Role
echo "[1/10] Checking IAM Role: ${ROLE_NAME}"
if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  echo "  -> Found. Importing..."
  terraform import -var-file=../env.tfvars \
    'module.rke2.aws_iam_role.nodes' \
    "${ROLE_NAME}" 2>/dev/null && echo "  -> Success" || echo "  -> Already in state or failed"
else
  echo "  -> Not found in AWS. Skipping."
fi

# 2. IAM Instance Profile
echo "[2/10] Checking IAM Instance Profile: ${PROFILE_NAME}"
if aws iam get-instance-profile --instance-profile-name "${PROFILE_NAME}" >/dev/null 2>&1; then
  echo "  -> Found. Importing..."
  terraform import -var-file=../env.tfvars \
    'module.rke2.aws_iam_instance_profile.nodes' \
    "${PROFILE_NAME}" 2>/dev/null && echo "  -> Success" || echo "  -> Already in state or failed"
else
  echo "  -> Not found in AWS. Skipping."
fi

# 3. IAM Role Policy Attachment (SSM Core)
echo "[3/10] Checking IAM Role Policy Attachment (SSM Core)"
if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  POLICY_ARN="arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ATTACHED=$(aws iam list-attached-role-policies --role-name "${ROLE_NAME}" \
    --query "AttachedPolicies[?PolicyArn=='${POLICY_ARN}'].PolicyArn" --output text 2>/dev/null)
  if [ -n "$ATTACHED" ]; then
    echo "  -> Found. Importing..."
    terraform import -var-file=../env.tfvars \
      'module.rke2.aws_iam_role_policy_attachment.ssm_core' \
      "${ROLE_NAME}/${POLICY_ARN}" 2>/dev/null && echo "  -> Success" || echo "  -> Already in state or failed"
  else
    echo "  -> Policy not attached. Skipping."
  fi
else
  echo "  -> Role not found. Skipping."
fi

# 4. Security Group
echo "[4/10] Checking Security Group: ${SG_NAME}"
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${SG_NAME}" \
  --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)

if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
  echo "  -> Found: ${SG_ID}. Importing..."
  terraform import -var-file=../env.tfvars \
    'module.rke2.aws_security_group.nodes' \
    "${SG_ID}" 2>/dev/null && echo "  -> Success" || echo "  -> Already in state or failed"
else
  echo "  -> Not found in AWS. Skipping."
fi

# 5. Internal NLB
echo "[5/10] Checking Internal NLB: ${NLB_NAME}"
NLB_ARN=$(aws elbv2 describe-load-balancers \
  --names "${NLB_NAME}" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || echo "")

if [ -n "$NLB_ARN" ] && [ "$NLB_ARN" != "None" ]; then
  echo "  -> Found: ${NLB_ARN}. Importing..."
  terraform import -var-file=../env.tfvars \
    'module.rke2.aws_lb.rke2[0]' \
    "${NLB_ARN}" 2>/dev/null && echo "  -> Success" || echo "  -> Already in state or failed"
else
  echo "  -> Not found in AWS. Skipping."
fi

# 6. Target Group - 9345
echo "[6/10] Checking Target Group: ${TG_9345_NAME}"
TG_9345_ARN=$(aws elbv2 describe-target-groups \
  --names "${TG_9345_NAME}" \
  --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "")

if [ -n "$TG_9345_ARN" ] && [ "$TG_9345_ARN" != "None" ]; then
  echo "  -> Found: ${TG_9345_ARN}. Importing..."
  terraform import -var-file=../env.tfvars \
    'module.rke2.aws_lb_target_group.supervisor[0]' \
    "${TG_9345_ARN}" 2>/dev/null && echo "  -> Success" || echo "  -> Already in state or failed"
else
  echo "  -> Not found in AWS. Skipping."
fi

# 7. Target Group - 6443
echo "[7/10] Checking Target Group: ${TG_6443_NAME}"
TG_6443_ARN=$(aws elbv2 describe-target-groups \
  --names "${TG_6443_NAME}" \
  --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "")

if [ -n "$TG_6443_ARN" ] && [ "$TG_6443_ARN" != "None" ]; then
  echo "  -> Found: ${TG_6443_ARN}. Importing..."
  terraform import -var-file=../env.tfvars \
    'module.rke2.aws_lb_target_group.apiserver[0]' \
    "${TG_6443_ARN}" 2>/dev/null && echo "  -> Success" || echo "  -> Already in state or failed"
else
  echo "  -> Not found in AWS. Skipping."
fi

# ============================================
# Public Ingress NLB Resources
# ============================================

# 8. Public Ingress NLB
echo "[8/10] Checking Public Ingress NLB: ${INGRESS_NLB_NAME}"
INGRESS_NLB_ARN=$(aws elbv2 describe-load-balancers \
  --names "${INGRESS_NLB_NAME}" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || echo "")

if [ -n "$INGRESS_NLB_ARN" ] && [ "$INGRESS_NLB_ARN" != "None" ]; then
  echo "  -> Found: ${INGRESS_NLB_ARN}. Importing..."
  terraform import -var-file=../env.tfvars \
    'module.rke2.aws_lb.ingress[0]' \
    "${INGRESS_NLB_ARN}" 2>/dev/null && echo "  -> Success" || echo "  -> Already in state or failed"
else
  echo "  -> Not found in AWS. Skipping."
fi

# 9. Target Group - HTTP (Ingress)
echo "[9/10] Checking Target Group: ${TG_HTTP_NAME}"
TG_HTTP_ARN=$(aws elbv2 describe-target-groups \
  --names "${TG_HTTP_NAME}" \
  --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "")

if [ -n "$TG_HTTP_ARN" ] && [ "$TG_HTTP_ARN" != "None" ]; then
  echo "  -> Found: ${TG_HTTP_ARN}. Importing..."
  terraform import -var-file=../env.tfvars \
    'module.rke2.aws_lb_target_group.ingress_http[0]' \
    "${TG_HTTP_ARN}" 2>/dev/null && echo "  -> Success" || echo "  -> Already in state or failed"
else
  echo "  -> Not found in AWS. Skipping."
fi

# 10. Target Group - HTTPS (Ingress)
echo "[10/10] Checking Target Group: ${TG_HTTPS_NAME}"
TG_HTTPS_ARN=$(aws elbv2 describe-target-groups \
  --names "${TG_HTTPS_NAME}" \
  --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "")

if [ -n "$TG_HTTPS_ARN" ] && [ "$TG_HTTPS_ARN" != "None" ]; then
  echo "  -> Found: ${TG_HTTPS_ARN}. Importing..."
  terraform import -var-file=../env.tfvars \
    'module.rke2.aws_lb_target_group.ingress_https[0]' \
    "${TG_HTTPS_ARN}" 2>/dev/null && echo "  -> Success" || echo "  -> Already in state or failed"
else
  echo "  -> Not found in AWS. Skipping."
fi

echo ""
echo "=============================================="
echo "Import process completed!"
echo "=============================================="
echo ""
echo "Next steps:"
echo "  1. Run 'terraform plan -var-file=../env.tfvars' to verify"
echo "  2. Run 'terraform apply -var-file=../env.tfvars' to apply changes"
echo ""
