#!/bin/bash
# =============================================================================
# Harbor Proxy Cache Setup Script
# Installed to: /opt/harbor/setup-proxy-cache.sh
# =============================================================================

set -uo pipefail
exec > >(tee -a /var/log/harbor-proxy-cache.log) 2>&1

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
GREEN=$'\e[32m'
YELLOW=$'\e[33m'
CYAN=$'\e[36m'
DIM=$'\e[2m'
NC=$'\e[0m'

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------
ok()     { echo -e "  ${GREEN}✓${NC} $*"; }
warn()   { echo -e "  ${YELLOW}!${NC} $*"; }
info()   { echo -e "  ${DIM}$*${NC}"; }
header() { echo -e "\n${CYAN}[Proxy Cache]${NC} $*"; }

create_proxy() {
  local NAME="$1" URL="$2" TYPE="${3:-docker-hub}"
  info "Creating: $NAME -> $URL"
  
  # Check if project exists
  curl -fsSk -u "$AUTH" "$API/projects/$NAME" 2>/dev/null | grep -q "$NAME" && return 0
  
  # Create registry endpoint
  curl -fsSk -u "$AUTH" -X POST "$API/registries" -H "Content-Type: application/json" \
    -d "{\"name\":\"$NAME-ep\",\"url\":\"$URL\",\"type\":\"$TYPE\",\"insecure\":false}" 2>/dev/null || true
  sleep 1
  
  # Get endpoint ID
  local EID=$(curl -fsSk -u "$AUTH" "$API/registries" 2>/dev/null \
    | grep -o "\"id\":[0-9]*,\"name\":\"$NAME-ep\"" \
    | grep -o "\"id\":[0-9]*" | cut -d: -f2 || echo "1")
  
  # Create project
  curl -fsSk -u "$AUTH" -X POST "$API/projects" -H "Content-Type: application/json" \
    -d "{\"project_name\":\"$NAME\",\"public\":true,\"registry_id\":$EID}" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------
SCHEME="http"
[[ "$HARBOR_ENABLE_TLS" == "true" ]] && SCHEME="https"

API="$SCHEME://127.0.0.1/api/v2.0"
AUTH="admin:$HARBOR_ADMIN_PASSWORD"

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
header "Setting up proxy cache projects"

create_proxy "$HARBOR_PROXY_CACHE_PROJECT" "https://hub.docker.com" "docker-hub"
create_proxy "k8s-proxy" "https://registry.k8s.io" "docker-registry"
create_proxy "ghcr-proxy" "https://ghcr.io" "docker-registry"
create_proxy "quay-proxy" "https://quay.io" "docker-registry"
create_proxy "gcr-proxy" "https://gcr.io" "docker-registry"
create_proxy "rancher-proxy" "https://registry.rancher.com" "docker-registry"

ok "Proxy cache setup completed"
