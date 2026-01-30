#!/bin/bash
# =============================================================================
# Harbor Helm Chart Seeding Script (Server-side)
# Installed to: /opt/harbor/seed-helm-charts.sh
# =============================================================================

set -uo pipefail

LOG_FILE="/var/log/harbor-helm-seed.log"
exec >> "$LOG_FILE" 2>&1

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
GREEN=$'\e[32m'
RED=$'\e[31m'
YELLOW=$'\e[33m'
CYAN=$'\e[36m'
DIM=$'\e[2m'
NC=$'\e[0m'

export HOME=/root
export HELM_EXPERIMENTAL_OCI=1

API_HOST="127.0.0.1"
API_URL="http://$API_HOST/api/v2.0"
AUTH="admin:$HARBOR_ADMIN_PASSWORD"
OCI_REGISTRY_HOST="$API_HOST"
OCI_URL="oci://$OCI_REGISTRY_HOST/helm-charts"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------
ok()     { echo -e "  ${GREEN}✓${NC} $*"; }
fail()   { echo -e "  ${RED}✗${NC} $*"; }
warn()   { echo -e "  ${YELLOW}!${NC} $*"; }
info()   { echo -e "  ${DIM}$*${NC}"; }
header() { echo -e "\n${CYAN}[$1]${NC} $2"; }

retry() {
  local max="$1" delay="$2" attempt=1
  shift 2
  until "$@"; do
    if ((attempt >= max)); then
      fail "Command failed after $max attempts: $*"
      return 1
    fi
    warn "Attempt $attempt failed, retrying in ${delay}s..."
    ((attempt++))
    sleep "$delay"
  done
  ok "Command succeeded"
}

wait_harbor_healthy() {
  header 1 "Waiting for Harbor"
  for i in {1..60}; do
    if curl -fsSk "$API_URL/health" 2>/dev/null | grep -q '"status":"healthy"'; then
      ok "Harbor is healthy"
      return 0
    fi
    info "Harbor not ready yet (attempt $i/60)..."
    sleep 10
  done
  fail "Harbor health check timed out"
  return 1
}

install_helm() {
  header 2 "Helm Installation"
  if command -v helm &>/dev/null; then
    ok "Helm already installed: $(helm version --short)"
    return 0
  fi
  
  info "Installing Helm..."
  local script="/tmp/get-helm-3.sh"
  local attempt=0 max_attempts=3
  
  while ((attempt < max_attempts)); do
    if curl -fsSL -o "$script" https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 2>&1; then
      chmod +x "$script"
      break
    fi
    ((attempt++))
    warn "Download attempt $attempt failed, retrying in 10s..."
    sleep 10
  done
  
  [[ ! -f "$script" ]] && { fail "Failed to download Helm install script"; return 1; }
  
  if bash "$script" 2>&1; then
    rm -f "$script"
    ok "Helm installed successfully"
    return 0
  else
    rm -f "$script"
    fail "Helm installation failed"
    return 1
  fi
}

create_helm_project() {
  header 3 "Creating helm-charts Project"
  local resp
  resp=$(curl -fsSk -u "$AUTH" -w "%{http_code}" -o /dev/null \
    -X POST "$API_URL/projects" \
    -H "Content-Type: application/json" \
    -d '{"project_name":"helm-charts","public":true}' 2>/dev/null) || true
  
  case "$resp" in
    201) ok "helm-charts project created" ;;
    409) ok "helm-charts project already exists" ;;
    *)   warn "Project creation returned: $resp (may already exist)" ;;
  esac
}

login_registry() {
  info "Logging into Harbor OCI registry at $OCI_REGISTRY_HOST..."
  if echo "$HARBOR_ADMIN_PASSWORD" | helm registry login "$OCI_REGISTRY_HOST" -u admin --password-stdin --plain-http 2>&1; then
    ok "Helm registry login successful"
    return 0
  else
    fail "Helm registry login failed"
    return 1
  fi
}

seed_chart() {
  local repo_name="$1" repo_url="$2" chart_name="$3" chart_version="$4"
  
  header "Seed" "$chart_name (version: $chart_version)"
  cd /tmp
  rm -f ${chart_name}*.tgz 2>/dev/null || true
  
  helm repo add "$repo_name" "$repo_url" --force-update 2>&1 || { fail "Failed to add repo: $repo_name"; return 1; }
  helm repo update "$repo_name" 2>&1 || true
  helm pull "$repo_name/$chart_name" --version "$chart_version" 2>&1 || { fail "Failed to pull chart: $repo_name/$chart_name:$chart_version"; return 1; }
  
  local tgz_file=$(ls ${chart_name}*.tgz 2>/dev/null | head -1)
  [[ -z "$tgz_file" ]] && { fail "Chart file not found after pull"; return 1; }
  
  if helm push "$tgz_file" "$OCI_URL" --plain-http 2>&1; then
    ok "Pushed: $chart_name:$chart_version"
  else
    fail "Failed to push chart: $chart_name"
    rm -f "$tgz_file" 2>/dev/null || true
    return 1
  fi
  
  rm -f "$tgz_file" 2>/dev/null || true
  return 0
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  echo -e "\n=== Helm Chart Seeding Started: $(date) ===\n"
  
  wait_harbor_healthy || exit 1
  install_helm || exit 1
  create_helm_project
  
  header 4 "Registry Login"
  retry 5 10 login_registry || {
    fail "Cannot login to registry, aborting seeding"
    exit 1
  }
  
  local failed=0
  
  seed_chart "argo" "https://argoproj.github.io/argo-helm" "argo-cd" "$HARBOR_ARGOCD_VER" || ((failed++))
  seed_chart "jetstack" "https://charts.jetstack.io" "cert-manager" "$HARBOR_CERTMANAGER_VER" || ((failed++))
  seed_chart "rancher" "https://releases.rancher.com/server-charts/stable" "rancher" "$HARBOR_RANCHER_VER" || ((failed++))
  
  helm repo remove argo jetstack rancher 2>/dev/null || true
  
  if ((failed > 0)); then
    warn "Helm seeding completed with $failed failures"
    exit 1
  fi
  
  echo -e "\n=== Helm Chart Seeding Completed Successfully: $(date) ===\n"
}

main "$@"
