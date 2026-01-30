#!/bin/bash
# =============================================================================
# Seed Harbor Proxy Cache with RKE2 System Images
# Usage: sudo ./seed-harbor-cache-rke2.sh
#        sudo RKE2_VERSION=v1.31.6+rke2r1 SOURCE=github ./seed-harbor-cache-rke2.sh
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

SOURCE="${SOURCE:-github}"
RKE2_VERSION="${RKE2_VERSION:-}"

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
echo -e "\n${BOLD}RKE2 Harbor Cache Seeding${NC}\n"

# Derive RKE2 version if not provided
if [[ -z "$RKE2_VERSION" ]]; then
  if command -v rke2 >/dev/null 2>&1; then
    RKE2_VERSION="$(rke2 --version 2>/dev/null | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+\+rke2r[0-9]+' | head -n1 || true)"
  fi
fi

[[ -z "$RKE2_VERSION" ]] && fail "RKE2_VERSION not detected. Set RKE2_VERSION=vX.Y.Z+rke2rN and retry."

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64)  IMGARCH="amd64" ;;
  aarch64|arm64) IMGARCH="arm64" ;;
  *)             IMGARCH="amd64" ;;
esac

info "RKE2 Version: $RKE2_VERSION"
info "Architecture: $IMGARCH"
info "Source: $SOURCE"

CRICTL="/var/lib/rancher/rke2/bin/crictl"
CRICTL_CFG="/var/lib/rancher/rke2/agent/etc/crictl.yaml"

[[ ! -x "$CRICTL" ]] || [[ ! -f "$CRICTL_CFG" ]] && \
  fail "crictl or CRI config not found. Is RKE2 installed and running?"

export CRI_CONFIG_FILE="$CRICTL_CFG"
LIST_FILE="/var/lib/rancher/rke2/agent/images/00-rke2-system-images-${IMGARCH}.txt"
MARKER="/var/lib/rancher/rke2/agent/images/.prefetch_done_${RKE2_VERSION}"

mkdir -p /var/lib/rancher/rke2/agent/images

# -----------------------------------------------------------------------------
# Check Marker
# -----------------------------------------------------------------------------
if [[ -f "$MARKER" ]]; then
  ok "Prefetch already done ($MARKER). Delete marker to re-run."
  exit 0
fi

# -----------------------------------------------------------------------------
# Download Image List
# -----------------------------------------------------------------------------
header 1 "Downloading Image List"
if [[ "$SOURCE" == "prime" ]]; then
  PRIMARY_URL="https://prime.ribs.rancher.io/rke2/${RKE2_VERSION}/rke2-images.linux-${IMGARCH}.txt"
  FALLBACK_URL="https://github.com/rancher/rke2/releases/download/${RKE2_VERSION}/rke2-images.linux-${IMGARCH}.txt"
else
  PRIMARY_URL="https://github.com/rancher/rke2/releases/download/${RKE2_VERSION}/rke2-images.linux-${IMGARCH}.txt"
  FALLBACK_URL="https://prime.ribs.rancher.io/rke2/${RKE2_VERSION}/rke2-images.linux-${IMGARCH}.txt"
fi

info "Primary: $PRIMARY_URL"
if ! curl -fsSL "$PRIMARY_URL" -o "$LIST_FILE"; then
  warn "Primary failed, trying fallback: $FALLBACK_URL"
  curl -fsSL "$FALLBACK_URL" -o "$LIST_FILE" || fail "Failed to download image list"
fi

sed -i '/^\s*$/d' "$LIST_FILE"
sed -i '/^\s*#/d' "$LIST_FILE"
ok "Image list downloaded"

# -----------------------------------------------------------------------------
# Pull Images
# -----------------------------------------------------------------------------
header 2 "Pulling Images via CRI"
info "This will populate Harbor proxy cache if registries.yaml is configured"

FAIL=0
while read -r IMG; do
  [[ -z "$IMG" ]] && continue
  info "Pulling: $IMG"
  "$CRICTL" pull "$IMG" || FAIL=1
done < "$LIST_FILE"

touch "$MARKER"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
if [[ "$FAIL" == "0" ]]; then
  ok "Prefetch completed. Harbor proxy-cache projects should now show cached repos/images."
else
  warn "Prefetch completed with errors. Some images may not have been cached."
  exit 2
fi
