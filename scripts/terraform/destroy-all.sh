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
