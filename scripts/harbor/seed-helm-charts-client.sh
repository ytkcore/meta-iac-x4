#!/bin/bash
# =============================================================================
# Helm Chart Seeding Script
# Harbor OCI registry에 Helm 차트를 시딩합니다.
#
# Usage:
#   ./seed-helm-charts.sh <HARBOR_HOST> <PASSWORD> [OPTIONS]
#
# Options:
#   --argocd-version      ArgoCD version (default: 5.55.0)
#   --certmanager-version cert-manager version (default: v1.14.5)
#   --rancher-version     Rancher version (default: 2.10.3)
#   --insecure            Skip TLS verification
#   --dry-run             Print commands only
# =============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# Config
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

ARGOCD_VER="5.55.0"
CERTMANAGER_VER="v1.14.5"
RANCHER_VER="2.10.3"
INSECURE=""
DRY_RUN=false

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
    *) log_error "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "$HARBOR_HOST" || -z "$ADMIN_PASS" ]]; then
  echo "Usage: $0 <HARBOR_HOST> <PASSWORD> [OPTIONS]"
  exit 1
fi

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------
detect_scheme() {
  if curl -fsSk --connect-timeout 5 "https://$HARBOR_HOST/api/v2.0/health" &>/dev/null; then
    echo "https"
  elif curl -fsSk --connect-timeout 5 "http://$HARBOR_HOST/api/v2.0/health" &>/dev/null; then
    echo "http"
  else
    log_error "Cannot connect to Harbor at $HARBOR_HOST"
    exit 1
  fi
}

wait_harbor_healthy() {
  log_info "Checking Harbor health..."
  for i in {1..30}; do
    if curl -fsSk "$API_URL/health" 2>/dev/null | grep -q '"status":"healthy"'; then
      log_info "Harbor is healthy"
      return 0
    fi
    log_warn "Harbor not ready (attempt $i/30)..."
    sleep 5
  done
  log_error "Harbor health check timed out"
  return 1
}

create_helm_project() {
  log_info "Creating helm-charts project..."
  local resp
  resp=$(curl -fsSk -u "$AUTH" -w "%{http_code}" -o /dev/null \
    -X POST "$API_URL/projects" \
    -H "Content-Type: application/json" \
    -d '{"project_name":"helm-charts","public":true}' 2>/dev/null) || true

  case "$resp" in
    201) log_info "helm-charts project created" ;;
    409) log_info "helm-charts project already exists" ;;
    *)   log_warn "Project creation returned: $resp" ;;
  esac
}

login_registry() {
  log_info "Logging into Harbor OCI registry..."
  local flags=""
  [[ "$SCHEME" == "http" ]] && flags="--insecure"

  if $DRY_RUN; then
    echo "  [DRY-RUN] helm registry login $HARBOR_HOST -u admin $flags"
    return 0
  fi

  if echo "$ADMIN_PASS" | helm registry login "$HARBOR_HOST" -u admin --password-stdin $flags 2>&1; then
    log_info "Registry login successful"
  else
    log_error "Registry login failed"
    return 1
  fi
}

seed_chart() {
  local repo_name="$1" repo_url="$2" chart_name="$3" chart_version="$4"

  log_info "Seeding: $chart_name ($chart_version)"

  if $DRY_RUN; then
    echo "  [DRY-RUN] helm pull $repo_name/$chart_name --version $chart_version"
    echo "  [DRY-RUN] helm push ${chart_name}-*.tgz $OCI_URL $INSECURE"
    return 0
  fi

  cd /tmp
  rm -f "${chart_name}"*.tgz 2>/dev/null || true

  # Add & update repo
  helm repo add "$repo_name" "$repo_url" --force-update 2>&1 || { log_error "Failed to add repo: $repo_name"; return 1; }
  helm repo update "$repo_name" 2>&1 || true

  # Pull chart
  helm pull "$repo_name/$chart_name" --version "$chart_version" 2>&1 || { log_error "Failed to pull: $chart_name:$chart_version"; return 1; }

  local tgz=$(ls "${chart_name}"*.tgz 2>/dev/null | head -1)
  [[ -z "$tgz" ]] && { log_error "Chart file not found"; return 1; }

  # Push to OCI
  local push_flags=""
  [[ "$SCHEME" == "http" || -n "$INSECURE" ]] && push_flags="--insecure-skip-tls-verify"

  if helm push "$tgz" "$OCI_URL" $push_flags 2>&1; then
    log_info "Pushed: $chart_name:$chart_version"
  else
    log_error "Failed to push: $chart_name"
    rm -f "$tgz"
    return 1
  fi

  rm -f "$tgz"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
SCHEME=$(detect_scheme)
API_URL="$SCHEME://$HARBOR_HOST/api/v2.0"
AUTH="admin:$ADMIN_PASS"
OCI_URL="oci://$HARBOR_HOST/helm-charts"

log_info "Harbor: $HARBOR_HOST (scheme: $SCHEME)"

command -v helm &>/dev/null || { log_error "Helm not installed"; exit 1; }

wait_harbor_healthy || exit 1
create_helm_project
login_registry || exit 1

failed=0
seed_chart "argo"     "https://argoproj.github.io/argo-helm"             "argo-cd"      "$ARGOCD_VER"      || ((failed++))
seed_chart "jetstack" "https://charts.jetstack.io"                       "cert-manager" "$CERTMANAGER_VER" || ((failed++))
seed_chart "rancher"  "https://releases.rancher.com/server-charts/stable" "rancher"      "$RANCHER_VER"     || ((failed++))

# Cleanup
helm repo remove argo jetstack rancher 2>/dev/null || true

if ((failed > 0)); then
  log_error "Seeding completed with $failed failures"
  exit 1
fi

log_info "All charts seeded successfully!"
