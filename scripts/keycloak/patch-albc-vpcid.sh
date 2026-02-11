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

header "ALBC VPC ID 패치 (Load Balancer 설정)"

# Get VPC ID from 50-rke2
info "50-rke2 스택에서 VPC ID 조회 중..."

VPC_ID=$(cd "${PROJECT_ROOT}/stacks/${ENV}/50-rke2" && \
  terraform output -raw vpc_id 2>/dev/null || echo "")

if [[ -z "$VPC_ID" ]]; then
  err "VPC ID를 찾을 수 없습니다. 50-rke2 스택이 배포되었는지 확인하세요."
  exit 1
fi
ok "VPC ID: ${VPC_ID}"

# Get cluster name
CLUSTER_NAME=$(cd "${PROJECT_ROOT}/stacks/${ENV}/50-rke2" && \
  terraform output -raw cluster_name 2>/dev/null || echo "meta-${ENV}-k8s")

ok "클러스터 이름: ${CLUSTER_NAME}"

# Patch ALBC yaml
info "ALBC ArgoCD App 설정 패치 중..."

if [[ "$(uname)" == "Darwin" ]]; then
  sed -i '' "s|vpcId: \"\".*|vpcId: \"${VPC_ID}\"|g" "${ALBC_YAML}"
  sed -i '' "s|clusterName: .*|clusterName: ${CLUSTER_NAME}|g" "${ALBC_YAML}"
else
  sed -i "s|vpcId: \"\".*|vpcId: \"${VPC_ID}\"|g" "${ALBC_YAML}"
  sed -i "s|clusterName: .*|clusterName: ${CLUSTER_NAME}|g" "${ALBC_YAML}"
fi

ok "ALBC 설정 파일 패치 완료"
info "파일: ${ALBC_YAML}"

# Verify
echo ""
grep -E "(vpcId|clusterName)" "${ALBC_YAML}" | head -5
echo ""

checkpoint "ALBC 설정 완료"
info "Git Commit 후 ArgoCD가 자동으로 설정을 동기화합니다."
