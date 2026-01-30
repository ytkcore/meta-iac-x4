#!/bin/bash
# =============================================================================
# Helm Chart Seeding Script (Client-side)
# Usage: ./seed-helm-charts-client.sh <HARBOR_HOST> <PASSWORD> [OPTIONS]
#
# Options:
#   --argocd-version      ArgoCD version (default: 5.55.0)
#   --certmanager-version cert-manager version (default: v1.14.5)
#   --rancher-version     Rancher version (default: 2.10.3)
#   --insecure            Skip TLS verification
#   --dry-run             Print commands only
# -----------------------------------------------------------------------------

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

ARGOCD_VER="5.55.0"
CERTMANAGER_VER="v1.14.5"
RANCHER_VER="2.10.3"
INSECURE=""
DRY_RUN=false

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------
ok()     { echo -e "  ${GREEN}✓${NC} $*"; }
fail()   { echo -e "  ${RED}✗${NC} $*"; return 1; }
warn()   { echo -e "  ${YELLOW}!${NC} $*"; }
info()   { echo -e "  ${DIM}$*${NC}"; }
header() { echo -e "\n${CYAN}${BOLD}[$1]${NC} $2"; }

detect_scheme() {
  if curl -fsSk --connect-timeout 5 "https://$HARBOR_HOST/api/v2.0/health" &>/dev/null; then
    echo "https"
  elif curl -fsSk --connect-timeout 5 "http://$HARBOR_HOST/api/v2.0/health" &>/dev/null; then
    echo "http"
  else
    fail "Cannot connect to Harbor at $HARBOR_HOST"
    exit 1
  fi
}

wait_harbor_healthy() {
  info "Checking Harbor health..."
  for i in {1..30}; do
    if curl -fsSk "$API_URL/health" 2>/dev/null | grep -q '"status":"healthy"'; then
      ok "Harbor is healthy"
      return 0
    fi
    warn "Harbor not ready (attempt $i/30)..."
    sleep 5
  done
  fail "Harbor health check timed out"
  return 1
}

create_helm_project() {
  info "Creating helm-charts project..."
  local resp
  resp=$(curl -fsSk -u "$AUTH" -w "%{http_code}" -o /dev/null \
    -X POST "$API_URL/projects" \
    -H "Content-Type: application/json" \
    -d '{"project_name":"helm-charts","public":true}' 2>/dev/null) || true

  case "$resp" in
    201) ok "helm-charts project created" ;;
    409) ok "helm-charts project already exists" ;;
    *)   warn "Project creation returned: $resp" ;;
  esac
}

login_registry() {
  info "Logging into Harbor OCI registry..."
  local flags=""
  [[ "$SCHEME" == "http" ]] && flags="--insecure"

  if $DRY_RUN; then
    echo "  [DRY-RUN] helm registry login $HARBOR_HOST -u admin $flags"
    return 0
  fi

  if echo "$ADMIN_PASS" | helm registry login "$HARBOR_HOST" -u admin --password-stdin $flags 2>&1; then
    ok "Registry login successful"
  else
    fail "Registry login failed"
    return 1
  fi
}

seed_chart() {
  local repo_name="$1" repo_url="$2" chart_name="$3" chart_version="$4"

  header "Seed" "$chart_name ($chart_version)"

  if $DRY_RUN; then
    echo "  [DRY-RUN] helm pull $repo_name/$chart_name --version $chart_version"
    echo "  [DRY-RUN] helm push ${chart_name}-*.tgz $OCI_URL $INSECURE"
    return 0
  fi

  cd /tmp
  rm -f "${chart_name}"*.tgz 2>/dev/null || true

  helm repo add "$repo_name" "$repo_url" --force-update 2>&1 || { fail "Failed to add repo: $repo_name"; return 1; }
  helm repo update "$repo_name" 2>&1 || true
  helm pull "$repo_name/$chart_name" --version "$chart_version" 2>&1 || { fail "Failed to pull: $chart_name:$chart_version"; return 1; }

  local tgz=$(ls "${chart_name}"*.tgz 2>/dev/null | head -1)
  [[ -z "$tgz" ]] && { fail "Chart file not found"; return 1; }

  local push_flags=""
  [[ "$SCHEME" == "http" || -n "$INSECURE" ]] && push_flags="--insecure-skip-tls-verify"

  if helm push "$tgz" "$OCI_URL" $push_flags 2>&1; then
    ok "Pushed: $chart_name:$chart_version"
  else
    fail "Failed to push: $chart_name"
    rm -f "$tgz"
    return 1
  fi

  rm -f "$tgz"
}

# -----------------------------------------------------------------------------
# Parse Arguments
# -----------------------------------------------------------------------------
HARBOR_HOST="${1:-}"
ADMIN_PASS="${2:-}"
shift 2 || true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --argocd-version)      ARGOCD_VER="$2"; shift 2 ;;
    --certmanager-version) CERTMANAGER_VER="$2"; shift 2 ;;
    --rancher-version)     RANCHER_VER="$2"; shift 2 ;;
    --insecure)            INSECURE="--insecure-skip-tls-verify"; shift ;;
    --dry-run)             DRY_RUN=true; shift ;;
    *) fail "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "$HARBOR_HOST" || -z "$ADMIN_PASS" ]]; then
  echo "Usage: $0 <HARBOR_HOST> <PASSWORD> [OPTIONS]"
  exit 1
fi

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
echo -e "\n${BOLD}Helm Chart Seeding${NC}\n"

SCHEME=$(detect_scheme)
API_URL="$SCHEME://$HARBOR_HOST/api/v2.0"
AUTH="admin:$ADMIN_PASS"
OCI_URL="oci://$HARBOR_HOST/helm-charts"

info "Harbor: $HARBOR_HOST (scheme: $SCHEME)"

command -v helm &>/dev/null || { fail "Helm not installed"; exit 1; }

wait_harbor_healthy || exit 1
create_helm_project
login_registry || exit 1

failed=0
seed_chart "argo"     "https://argoproj.github.io/argo-helm"             "argo-cd"      "$ARGOCD_VER"      || ((failed++))
seed_chart "jetstack" "https://charts.jetstack.io"                       "cert-manager" "$CERTMANAGER_VER" || ((failed++))
seed_chart "rancher"  "https://releases.rancher.com/server-charts/stable" "rancher"      "$RANCHER_VER"     || ((failed++))

helm repo remove argo jetstack rancher 2>/dev/null || true

if ((failed > 0)); then
  fail "Seeding completed with $failed failures"
  exit 1
fi

ok "All charts seeded successfully"
