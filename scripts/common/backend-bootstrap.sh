#!/bin/bash
# =============================================================================
# Backend Bootstrap Script
# Usage: STATE_BUCKET=<bucket> STATE_REGION=<region> ./backend-bootstrap.sh
# =============================================================================

set -uo pipefail

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
GREEN=$'\e[32m'
RED=$'\e[31m'
YELLOW=$'\e[33m'
CYAN=$'\e[36m'
DIM=$'\e[2m'
NC=$'\e[0m'

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------
ok()     { echo -e "  ${GREEN}✓${NC} $*"; }
fail()   { echo -e "  ${RED}✗${NC} $*"; }
warn()   { echo -e "  ${YELLOW}!${NC} $*"; }
info()   { echo -e "  ${DIM}$*${NC}"; }
header() { echo -e "\n${CYAN}[$1]${NC} $2"; }

tf() { terraform -chdir="${BOOT_DIR}" "$@"; }

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOOT_DIR="${ROOT_DIR}/stacks/bootstrap-backend"

STATE_BUCKET="${STATE_BUCKET:?STATE_BUCKET is required}"
STATE_REGION="${STATE_REGION:-ap-northeast-2}"

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
header 1 "Terraform Init (${STATE_BUCKET} / ${STATE_REGION})"
tf init -upgrade=false -reconfigure >/dev/null
ok "Terraform initialized"

header 2 "Check Backend Bucket"
if aws s3api head-bucket --bucket "${STATE_BUCKET}" >/dev/null 2>&1; then
  warn "Bucket already exists. Importing into terraform state..."
  
  addrs=(
    "aws_s3_bucket.tfstate"
    "aws_s3_bucket_versioning.this"
    "aws_s3_bucket_public_access_block.this"
    "aws_s3_bucket_server_side_encryption_configuration.this"
    "aws_s3_bucket_policy.tls_only"
  )

  for addr in "${addrs[@]}"; do
    if ! tf state list 2>/dev/null | grep -q "^${addr}$"; then
      info "Importing ${addr}..."
      tf import \
        -var="state_bucket=${STATE_BUCKET}" \
        -var="state_region=${STATE_REGION}" \
        "${addr}" "${STATE_BUCKET}" >/dev/null 2>&1 || true
    fi
  done
  ok "Import completed"
else
  info "Bucket does not exist. It will be created by Terraform."
fi

header 3 "Apply Bootstrap"
tf apply -auto-approve \
  -var="state_bucket=${STATE_BUCKET}" \
  -var="state_region=${STATE_REGION}"

ok "Backend bootstrap completed"
