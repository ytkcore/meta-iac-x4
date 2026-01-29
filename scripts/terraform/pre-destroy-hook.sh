#!/bin/bash
# =============================================================================
# Pre-Destroy Hook for Rancher/K8s Stacks
# Usage: ./pre-destroy-hook.sh <STACK>
# =============================================================================

set -uo pipefail

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
GREEN=$'\e[32m'
YELLOW=$'\e[33m'
CYAN=$'\e[36m'
DIM=$'\e[2m'
NC=$'\e[0m'

STACK="${1:-}"
RANCHER_STACKS="55-rancher 55-bootstrap"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------
ok()     { echo -e "  ${GREEN}✓${NC} $*"; }
warn()   { echo -e "  ${YELLOW}!${NC} $*"; }
info()   { echo -e "  ${DIM}$*${NC}"; }
header() { echo -e "\n${CYAN}[$STACK]${NC} $*"; }

# -----------------------------------------------------------------------------
# Check
# -----------------------------------------------------------------------------
if ! echo "$RANCHER_STACKS" | grep -qw "$STACK"; then
  exit 0
fi

# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------
header "Pre-destroy cleanup: Helm releases and namespaces"

info "Uninstalling rancher..."
helm uninstall rancher -n cattle-system 2>/dev/null || true

info "Uninstalling cert-manager..."
helm uninstall cert-manager -n cert-manager 2>/dev/null || true

info "Deleting namespaces..."
kubectl delete namespace cattle-system --ignore-not-found --timeout=60s 2>/dev/null || true
kubectl delete namespace cert-manager --ignore-not-found --timeout=60s 2>/dev/null || true

info "Cleaning up CRDs..."
kubectl delete crd -l app.kubernetes.io/name=cert-manager 2>/dev/null || true

ok "Pre-destroy cleanup completed"
