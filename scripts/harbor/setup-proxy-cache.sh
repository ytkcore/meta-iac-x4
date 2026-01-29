#!/bin/bash
# Harbor Proxy Cache Setup Script
# Installed to: /opt/harbor/setup-proxy-cache.sh
set -euo pipefail
exec > >(tee -a /var/log/harbor-proxy-cache.log) 2>&1

SCHEME="http"; [[ "$HARBOR_ENABLE_TLS" == "true" ]] && SCHEME="https"
API="$SCHEME://127.0.0.1/api/v2.0"
AUTH="admin:$HARBOR_ADMIN_PASSWORD"

create_proxy() {
  local NAME="$1" URL="$2" TYPE="${3:-docker-hub}"
  echo "[INFO] Creating: $NAME -> $URL"
  curl -fsSk -u "$AUTH" "$API/projects/$NAME" 2>/dev/null | grep -q "$NAME" && return 0
  curl -fsSk -u "$AUTH" -X POST "$API/registries" -H "Content-Type: application/json" \
    -d "{\"name\":\"$NAME-ep\",\"url\":\"$URL\",\"type\":\"$TYPE\",\"insecure\":false}" 2>/dev/null || true
  sleep 1
  local EID=$(curl -fsSk -u "$AUTH" "$API/registries" 2>/dev/null | grep -o "\"id\":[0-9]*,\"name\":\"$NAME-ep\"" | grep -o "\"id\":[0-9]*" | cut -d: -f2 || echo "1")
  curl -fsSk -u "$AUTH" -X POST "$API/projects" -H "Content-Type: application/json" \
    -d "{\"project_name\":\"$NAME\",\"public\":true,\"registry_id\":$EID}" 2>/dev/null || true
}

create_proxy "$HARBOR_PROXY_CACHE_PROJECT" "https://hub.docker.com" "docker-hub"
create_proxy "k8s-proxy" "https://registry.k8s.io" "docker-registry"
create_proxy "ghcr-proxy" "https://ghcr.io" "docker-registry"
create_proxy "quay-proxy" "https://quay.io" "docker-registry"
create_proxy "gcr-proxy" "https://gcr.io" "docker-registry"
create_proxy "rancher-proxy" "https://registry.rancher.com" "docker-registry"
echo "[OK] Proxy cache setup done"
