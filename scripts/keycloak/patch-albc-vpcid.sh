#!/bin/bash
# ==============================================================================
# ALBC VPC ID Patcher
#
# 50-rke2 Terraform output에서 VPC ID를 가져와
# ALBC ArgoCD App yaml에 자동 주입
#
# Usage:
#   ./scripts/keycloak/patch-albc-vpcid.sh
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=../common/logging.sh
source "${PROJECT_ROOT}/scripts/common/logging.sh"

ENV="${ENV:-dev}"
ALBC_YAML="${PROJECT_ROOT}/gitops-apps/bootstrap/aws-load-balancer-controller.yaml"

header "ALBC VPC ID Patch"

# Get VPC ID from 50-rke2
info "Fetching VPC ID from 50-rke2 stack..."

VPC_ID=$(cd "${PROJECT_ROOT}/stacks/${ENV}/50-rke2" && \
  terraform output -raw vpc_id 2>/dev/null || echo "")

if [[ -z "$VPC_ID" ]]; then
  err "VPC ID not found. Is 50-rke2 deployed?"
  exit 1
fi
ok "VPC ID: ${VPC_ID}"

# Get cluster name
CLUSTER_NAME=$(cd "${PROJECT_ROOT}/stacks/${ENV}/50-rke2" && \
  terraform output -raw cluster_name 2>/dev/null || echo "meta-${ENV}-k8s")

ok "Cluster Name: ${CLUSTER_NAME}"

# Patch ALBC yaml
info "Patching ALBC ArgoCD App..."

if [[ "$(uname)" == "Darwin" ]]; then
  sed -i '' "s|vpcId: \"\".*|vpcId: \"${VPC_ID}\"|g" "${ALBC_YAML}"
  sed -i '' "s|clusterName: .*|clusterName: ${CLUSTER_NAME}|g" "${ALBC_YAML}"
else
  sed -i "s|vpcId: \"\".*|vpcId: \"${VPC_ID}\"|g" "${ALBC_YAML}"
  sed -i "s|clusterName: .*|clusterName: ${CLUSTER_NAME}|g" "${ALBC_YAML}"
fi

ok "ALBC yaml patched"
info "File: ${ALBC_YAML}"

# Verify
echo ""
grep -E "(vpcId|clusterName)" "${ALBC_YAML}" | head -5
echo ""

checkpoint "ALBC VPC ID Patch Complete"
info "Git commit 후 ArgoCD가 자동 Sync합니다."
