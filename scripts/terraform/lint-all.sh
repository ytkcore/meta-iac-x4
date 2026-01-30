#!/bin/bash
# =============================================================================
# Run TFLint on All Modules and Stacks
# Usage: ./lint-all.sh
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
header() { echo -e "\n${CYAN}${BOLD}[TFLint]${NC} $*"; }

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------
command -v tflint >/dev/null 2>&1 || { fail "tflint not found."; exit 2; }

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
echo -e "\n${BOLD}TFLint - All Modules and Stacks${NC}\n"

header "Initializing TFLint"
tflint --init
ok "TFLint initialized"

FAILED=0
for dir in $(find modules stacks -mindepth 2 -maxdepth 2 -type d); do
  if ls "$dir"/*.tf >/dev/null 2>&1; then
    header "$dir"
    if (cd "$dir" && tflint); then
      ok "Passed"
    else
      fail "Issues found"
      FAILED=$((FAILED + 1))
    fi
  fi
done

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
if [[ $FAILED -eq 0 ]]; then
  ok "All linting completed successfully"
else
  warn "Linting completed with $FAILED failures"
  exit 1
fi
