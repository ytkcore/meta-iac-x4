#!/bin/bash
# =============================================================================
# Harbor Bootstrap Script
# Installed to: /opt/harbor/bootstrap.sh
# =============================================================================

set -uo pipefail
exec > >(tee -a /var/log/harbor-install.log) 2>&1

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

MARKER="/opt/harbor/.installed"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------
ok()     { echo -e "  ${GREEN}✓${NC} $*"; }
fail()   { echo -e "  ${RED}✗${NC} $*"; exit 1; }
warn()   { echo -e "  ${YELLOW}!${NC} $*"; }
info()   { echo -e "  ${DIM}$*${NC}"; }
header() { echo -e "\n${CYAN}${BOLD}[$1]${NC} $2"; }

retry() {
  local n=0 m="$1" d="$2"; shift 2
  until "$@"; do
    n=$((n+1))
    ((n>=m)) && return 1
    sleep "$d"
  done
}

wait_net() {
  for i in {1..60}; do
    ping -c1 -W2 8.8.8.8 &>/dev/null && return 0
    sleep 5
  done
  return 1
}

get_harbor_host() { grep -oP 'harbor\.[a-zA-Z0-9.-]+' "$1" 2>/dev/null | head -1; }

# -----------------------------------------------------------------------------
# Already Installed Check
# -----------------------------------------------------------------------------
echo -e "\n${BOLD}Harbor Installation${NC} - $(date '+%Y-%m-%d %H:%M:%S')\n"

if [[ -f "$MARKER" ]]; then
  ok "Already installed"
  systemctl enable --now docker || true
  [[ -f /opt/harbor/harbor/docker-compose.yml ]] && cd /opt/harbor/harbor && docker compose up -d || true
  exit 0
fi

# -----------------------------------------------------------------------------
# 1. Network
# -----------------------------------------------------------------------------
header 1 "Network Check"
wait_net && ok "Network available" || fail "No network connectivity"

# -----------------------------------------------------------------------------
# 2. Packages
# -----------------------------------------------------------------------------
header 2 "Installing Packages"
for i in {1..10}; do dnf -y makecache && break; sleep 10; done
retry 5 15 dnf -y install tar gzip openssl ca-certificates wget
command -v curl &>/dev/null || dnf -y install curl-minimal 2>/dev/null || dnf -y install curl --allowerasing || true
ok "Packages installed"

# -----------------------------------------------------------------------------
# 3. Docker
# -----------------------------------------------------------------------------
header 3 "Installing Docker"
if ! command -v docker &>/dev/null; then
  dnf -y install docker 2>/dev/null || {
    dnf -y install dnf-plugins-core || true
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || true
    retry 3 15 dnf -y install docker-ce docker-ce-cli containerd.io
  }
fi
systemctl enable docker && systemctl start docker
for i in {1..30}; do docker info &>/dev/null && break; sleep 3; done
docker info &>/dev/null || fail "Docker failed to start"
ok "Docker running"

# -----------------------------------------------------------------------------
# 4. Docker Compose
# -----------------------------------------------------------------------------
header 4 "Installing Docker Compose"
docker compose version &>/dev/null || {
  dnf -y install docker-compose-plugin 2>/dev/null || {
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -fsSL -o /usr/local/lib/docker/cli-plugins/docker-compose \
      "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-$(uname -m)"
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
  }
}
ok "Docker Compose installed"

# -----------------------------------------------------------------------------
# 5. Docker Configuration
# -----------------------------------------------------------------------------
header 5 "Configuring Docker"
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << EOF
{"insecure-registries":["127.0.0.1","$HARBOR_HOSTNAME","localhost"],"log-driver":"json-file","log-opts":{"max-size":"50m","max-file":"3"}}
EOF
systemctl restart docker && sleep 5
ok "Docker configured"

# -----------------------------------------------------------------------------
# 6. Download Harbor
# -----------------------------------------------------------------------------
header 6 "Downloading Harbor v${HARBOR_VERSION}"
cd /opt/harbor
retry 5 15 curl -fsSL -o harbor.tgz "https://github.com/goharbor/harbor/releases/download/v$HARBOR_VERSION/harbor-online-installer-v$HARBOR_VERSION.tgz"
tar -xzf harbor.tgz && cd /opt/harbor/harbor
ok "Harbor downloaded"

# -----------------------------------------------------------------------------
# 7. Configure Harbor
# -----------------------------------------------------------------------------
header 7 "Configuring Harbor"
cp harbor.yml.tmpl harbor.yml
sed -i "s|^hostname:.*|hostname: $HARBOR_HOSTNAME|" harbor.yml
sed -i "s|^harbor_admin_password:.*|harbor_admin_password: \"$HARBOR_ADMIN_PASSWORD\"|" harbor.yml
sed -i "s|^data_volume:.*|data_volume: $HARBOR_DATA_VOLUME|" harbor.yml
sed -i "s|^\(\s*password:\).*|\1 \"$HARBOR_DB_PASSWORD\"|" harbor.yml
sed -i '/^http:/,/^[a-z]/ { s|^\(\s*port:\).*|\1 80| }' harbor.yml
[[ "$HARBOR_ENABLE_TLS" != "true" ]] && sed -i '/^https:/,/^[a-z#]/ { s/^/#/ }' harbor.yml

if [[ "$HARBOR_STORAGE_TYPE" == "s3" && -n "$HARBOR_S3_BUCKET" ]]; then
  sed -i '/^storage_service:/,/^[a-z]/d' harbor.yml
  cat >> harbor.yml << EOF
storage_service:
  s3:
    accesskey: ""
    secretkey: ""
    region: $HARBOR_S3_REGION
    bucket: $HARBOR_S3_BUCKET
    rootdirectory: /harbor
EOF
fi

[[ "$HARBOR_ENABLE_TLS" == "true" ]] && \
  openssl req -x509 -nodes -newkey rsa:4096 \
    -keyout /data/cert/server.key -out /data/cert/server.crt \
    -days 3650 -subj "/CN=$HARBOR_HOSTNAME"
ok "Harbor configured"

# -----------------------------------------------------------------------------
# 8. Start Harbor
# -----------------------------------------------------------------------------
header 8 "Starting Harbor"
chmod +x prepare && ./prepare
mkdir -p /var/log/harbor /data/harbor /data/cert /data/database /data/redis /data/registry /data/secret/keys
docker compose up -d

SCHEME="http"
[[ "$HARBOR_ENABLE_TLS" == "true" ]] && SCHEME="https"

info "Waiting for Harbor health..."
for i in {1..60}; do
  curl -fsSk "$SCHEME://127.0.0.1/api/v2.0/health" 2>/dev/null | grep -q healthy && break
  sleep 10
done

touch "$MARKER" && rm -f /opt/harbor/harbor.tgz

ok "Harbor installed successfully"
info "URL: $SCHEME://$HARBOR_HOSTNAME"

# -----------------------------------------------------------------------------
# Post-Install Scripts
# -----------------------------------------------------------------------------
[[ -x /opt/harbor/setup-proxy-cache.sh ]] && nohup /opt/harbor/setup-proxy-cache.sh >> /var/log/harbor-proxy-cache.log 2>&1 &
[[ -x /opt/harbor/seed-helm-charts.sh ]] && nohup /opt/harbor/seed-helm-charts.sh >> /var/log/harbor-helm-seed.log 2>&1 &
