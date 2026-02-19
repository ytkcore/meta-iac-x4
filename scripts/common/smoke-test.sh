#!/bin/bash
# =============================================================================
# Platform Smoke Test
# =============================================================================
# Global Standard: Google SRE Post-Deploy Verification
# Validates all platform services are healthy after deployment/initialization.
# =============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logging.sh"

# ─── Configuration ──────────────────────────────────────────────────────────

PASS=0
FAIL=0
WARN=0

# Service → Namespace mapping
declare -A NAMESPACES
NAMESPACES[vault]="vault"
NAMESPACES[keycloak]="keycloak"
NAMESPACES[argocd]="argocd"
NAMESPACES[monitoring]="monitoring"
NAMESPACES[ingress]="ingress-nginx"
NAMESPACES[longhorn]="longhorn-system"
NAMESPACES[cert-manager]="cert-manager"
NAMESPACES[aipp]="aipp"

# Optional namespaces (no failure if missing)
OPTIONAL_NS=("aipp" "cattle-system" "opstart")

# ─── Helpers ────────────────────────────────────────────────────────────────

_check_kubectl() {
  if ! command -v kubectl &>/dev/null; then
    err "kubectl not found"
    exit 1
  fi
}

_is_optional() {
  local ns="$1"
  for opt in "${OPTIONAL_NS[@]}"; do
    [[ "$ns" == "$opt" ]] && return 0
  done
  return 1
}

_count() {
  local result="$1"
  case "$result" in
    pass) ((PASS++)) ;;
    fail) ((FAIL++)) ;;
    warn) ((WARN++)) ;;
  esac
}

# ─── Test Functions ─────────────────────────────────────────────────────────

test_cluster() {
  header "Kubernetes Cluster"

  if kubectl cluster-info &>/dev/null 2>&1; then
    ok "API Server reachable"
    _count pass
  else
    err "API Server unreachable"
    _count fail
    exit 1
  fi

  local nodes
  nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
  local ready
  ready=$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready' || true)

  if [[ "$ready" -eq "$nodes" && "$nodes" -gt 0 ]]; then
    ok "Nodes: ${ready}/${nodes} Ready"
    _count pass
  else
    err "Nodes: ${ready}/${nodes} Ready"
    _count fail
  fi
}

test_namespaces() {
  header "Namespace Health"

  for svc in "${!NAMESPACES[@]}"; do
    local ns="${NAMESPACES[$svc]}"

    if ! kubectl get ns "$ns" &>/dev/null 2>&1; then
      if _is_optional "$ns"; then
        warn "${svc} (${ns}) — namespace not found (optional, skipped)"
        _count warn
      else
        err "${svc} (${ns}) — namespace not found"
        _count fail
      fi
      continue
    fi

    local total not_ready
    total=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -v Completed | wc -l | tr -d ' ')
    not_ready=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -v Running | grep -v Completed | wc -l | tr -d ' ')

    if [[ "$total" -eq 0 ]]; then
      warn "${svc} (${ns}) — no pods found"
      _count warn
    elif [[ "$not_ready" -eq 0 ]]; then
      ok "${svc} (${ns}) — ${total} pods all Running"
      _count pass
    else
      err "${svc} (${ns}) — ${not_ready}/${total} pods not ready"
      _count fail
    fi
  done
}

test_ingress() {
  header "Ingress Endpoints"

  local ingresses
  ingresses=$(kubectl get ingress -A --no-headers 2>/dev/null)

  if [[ -z "$ingresses" ]]; then
    warn "No ingress resources found"
    _count warn
    return
  fi

  while IFS= read -r line; do
    local ns host
    ns=$(echo "$line" | awk '{print $1}')
    host=$(echo "$line" | awk '{print $4}')
    ok "${host} (${ns})"
    _count pass
  done <<< "$ingresses"
}

test_vault() {
  header "Vault Status"

  if ! kubectl get ns vault &>/dev/null 2>&1; then
    warn "Vault namespace not found"
    _count warn
    return
  fi

  local sealed
  sealed=$(kubectl exec -n vault vault-0 -- vault status -format=json 2>/dev/null | \
    grep -o '"sealed":[a-z]*' | cut -d: -f2 || echo "unknown")

  case "$sealed" in
    false)
      ok "Vault is Unsealed and Active"
      _count pass
      ;;
    true)
      err "Vault is SEALED — run unseal procedure"
      _count fail
      ;;
    *)
      warn "Cannot determine Vault status"
      _count warn
      ;;
  esac
}

test_certificates() {
  header "TLS Certificates"

  if ! kubectl get crd certificates.cert-manager.io &>/dev/null 2>&1; then
    warn "cert-manager CRDs not found"
    _count warn
    return
  fi

  local certs
  certs=$(kubectl get certificates -A --no-headers 2>/dev/null)

  if [[ -z "$certs" ]]; then
    warn "No certificates found"
    _count warn
    return
  fi

  while IFS= read -r line; do
    local ns name ready
    ns=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | awk '{print $2}')
    ready=$(echo "$line" | awk '{print $3}')

    if [[ "$ready" == "True" ]]; then
      ok "${name} (${ns}) — Valid"
      _count pass
    else
      err "${name} (${ns}) — Not Ready"
      _count fail
    fi
  done <<< "$certs"
}

# ─── Summary ────────────────────────────────────────────────────────────────

print_summary() {
  echo ""
  echo -e "${COLOR_BOLD}${COLOR_CYAN}"
  echo "  ╔══════════════════════════════════════════════════════════════╗"
  echo "  ║              🧪  Smoke Test Summary                        ║"
  echo "  ╚══════════════════════════════════════════════════════════════╝"
  echo -e "${COLOR_NC}"

  echo -e "  ${COLOR_GREEN}✓ Passed${COLOR_NC}: ${PASS}"
  echo -e "  ${COLOR_YELLOW}! Warnings${COLOR_NC}: ${WARN}"
  echo -e "  ${COLOR_RED}✗ Failed${COLOR_NC}: ${FAIL}"
  echo ""

  if [[ "$FAIL" -eq 0 ]]; then
    echo -e "  ${COLOR_GREEN}${COLOR_BOLD}🎉 All critical checks passed!${COLOR_NC}"
  else
    echo -e "  ${COLOR_RED}${COLOR_BOLD}⚠  ${FAIL} check(s) failed — review errors above${COLOR_NC}"
  fi

  echo -e "  ${COLOR_DIM}📖 Troubleshooting: docs/guides/post-deployment-operations-guide.md${COLOR_NC}"
  echo ""
}

# ─── Main ───────────────────────────────────────────────────────────────────

main() {
  _check_kubectl

  echo ""
  echo -e "${COLOR_BOLD}${COLOR_CYAN}"
  echo "  ╔══════════════════════════════════════════════════════════════╗"
  echo "  ║              🧪  Platform Smoke Test                       ║"
  echo "  ╠══════════════════════════════════════════════════════════════╣"
  echo "  ║  Date: $(date '+%Y-%m-%d %H:%M:%S')                              ║"
  echo "  ╚══════════════════════════════════════════════════════════════╝"
  echo -e "${COLOR_NC}"

  test_cluster
  test_namespaces
  test_ingress
  test_vault
  test_certificates
  print_summary

  [[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
}

main "$@"
