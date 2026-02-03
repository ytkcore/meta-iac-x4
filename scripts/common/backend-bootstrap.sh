#!/bin/bash
# =============================================================================
# Backend Bootstrap Script
# Usage: STATE_BUCKET=<bucket> STATE_REGION=<region> ./backend-bootstrap.sh
# =============================================================================

set -uo pipefail

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
# Colors
if [ -t 1 ]; then
  GREEN='\033[32m'
  RED='\033[31m'
  YELLOW='\033[33m'
  CYAN='\033[36m'
  BOLD='\033[1m'
  DIM='\033[2m'
  NC='\033[0m'
else
  GREEN='' RED='' YELLOW='' CYAN='' BOLD='' DIM='' NC=''
fi

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------
ok()     { echo -e "  ${GREEN}✓${NC} $*"; }
fail()   { echo -e "  ${RED}✗${NC} $*"; }
warn()   { echo -e "  ${YELLOW}!${NC} $*"; }
info()   { echo -e "  ${DIM}$*${NC}"; }
header() { echo -e "\n${CYAN}[$1]${NC} $2"; }

aws_exec() {
  if [ -z "${AWS_VAULT:-}" ]; then
    aws-vault exec devops -- "$@"
  else
    "$@"
  fi
}

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
if aws_exec aws s3api head-bucket --bucket "${STATE_BUCKET}" >/dev/null 2>&1; then
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
MAX_RETRIES=3
RETRY_COUNT=0
SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  info "Running terraform apply (Attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)..."
  if tf apply -auto-approve \
    -var="state_bucket=${STATE_BUCKET}" \
    -var="state_region=${STATE_REGION}"; then
    SUCCESS=true
    break
  else
    warn "Terraform apply failed. This might be due to S3 eventual consistency."
    RETRY_COUNT=$((RETRY_COUNT + 1))
    
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
      info "Waiting 10 seconds for AWS propagation before retrying..."
      sleep 10
    fi
  fi
done

if [ "$SUCCESS" = false ]; then
  fail "Backend bootstrap failed after $MAX_RETRIES attempts."
  exit 1
fi

# Final Verification: Ensure bucket is truly ready and tagging is readable
info "Final verification of bucket accessibility..."
for i in {1..6}; do
  if aws_exec aws s3api head-bucket --bucket "${STATE_BUCKET}" &>/dev/null; then
    # Try reading tags to be sure (where it usually fails)
    if aws_exec aws s3api get-bucket-tagging --bucket "${STATE_BUCKET}" &>/dev/null; then
      ok "Backend bucket '${STATE_BUCKET}' is fully ready and verified."
      exit 0
    fi
  fi
  info "  Waiting for S3 propagation... ($i/6) "
  sleep 5
done

warn "Bucket exists but tagging is not yet readable. Next steps might require a short wait."
ok "Backend bootstrap completed (Creation successful, but propagation pending)"
