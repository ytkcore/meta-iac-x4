#!/bin/bash
# =============================================================================
# Harbor Install Script (via SSM Config)
# Usage: ./install-harbor.sh <env> [name] [version]
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
fail()   { echo -e "  ${RED}✗${NC} $*"; exit 1; }
warn()   { echo -e "  ${YELLOW}!${NC} $*"; }
info()   { echo -e "  ${DIM}$*${NC}"; }
header() { echo -e "\n${CYAN}${BOLD}[$1]${NC} $2"; }

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------
ENV="${1:-dev}"
NAME="${2:-harbor}"
VERSION="${3:-2.9.1}"
SSM_PARAM="/harbor/${ENV}/${NAME}/config/yaml"

echo -e "\n${BOLD}Harbor Deployment${NC} (Env: $ENV, Ver: $VERSION)\n"

# -----------------------------------------------------------------------------
# 1. Docker Installation
# -----------------------------------------------------------------------------
header 1 "Docker Installation"
if ! command -v docker &> /dev/null; then
  dnf update -y && dnf install -y docker python3 tar gzip openssl jq
  dnf install -y docker-compose-plugin || \
    curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
  echo -e '#!/bin/bash\nexec docker compose "$@"' > /usr/bin/docker-compose && chmod +x /usr/bin/docker-compose
  systemctl enable --now docker
  ok "Docker installed"
else
  ok "Docker already installed"
fi

# -----------------------------------------------------------------------------
# 2. Download Harbor
# -----------------------------------------------------------------------------
header 2 "Downloading Harbor"
mkdir -p /opt/harbor /data/harbor /data/cert
cd /opt/harbor

if [[ ! -d "harbor" ]]; then
  curl -fsSL -o harbor.tgz "https://github.com/goharbor/harbor/releases/download/v${VERSION}/harbor-online-installer-v${VERSION}.tgz"
  tar -xzf harbor.tgz
  ok "Harbor downloaded"
else
  ok "Harbor already downloaded"
fi
cd harbor

# -----------------------------------------------------------------------------
# 3. Fetch Config from SSM
# -----------------------------------------------------------------------------
header 3 "Fetching Config from SSM"
info "Parameter: ${SSM_PARAM}"
aws ssm get-parameter --name "${SSM_PARAM}" --with-decryption --query "Parameter.Value" --output text > harbor.yml
ok "Config fetched"

# -----------------------------------------------------------------------------
# 4. TLS Certificate
# -----------------------------------------------------------------------------
header 4 "TLS Certificate"
if grep -q "https:" harbor.yml && [[ ! -f /data/cert/server.key ]]; then
  CN=$(grep 'hostname:' harbor.yml | awk '{print $2}')
  openssl req -x509 -nodes -newkey rsa:4096 \
    -keyout /data/cert/server.key -out /data/cert/server.crt \
    -days 3650 -subj "/CN=${CN}"
  ok "Self-signed cert generated"
else
  ok "Certificate exists or HTTPS not configured"
fi

# -----------------------------------------------------------------------------
# 5. Start Harbor
# -----------------------------------------------------------------------------
header 5 "Starting Harbor"
docker compose down || true
./prepare
docker compose up -d

ok "Harbor deployed successfully"