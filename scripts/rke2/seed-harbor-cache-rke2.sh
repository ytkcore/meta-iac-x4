#!/bin/bash
set -euo pipefail

# Seed Harbor Proxy Cache with RKE2 system images by pulling them via CRI (crictl).
#
# This is useful when:
# - registries.yaml is configured to mirror upstream registries through Harbor proxy-cache projects
# - but Harbor UI shows no cached repos/images yet (because nothing has pulled through Harbor)
#
# Usage:
#   sudo ./seed-harbor-cache-rke2.sh
#   sudo RKE2_VERSION=v1.31.6+rke2r1 SOURCE=github ./seed-harbor-cache-rke2.sh
#
# Notes:
# - Must be executed on an RKE2 node that has /var/lib/rancher/rke2/bin/crictl.
# - The node itself only talks to Harbor (internal), and Harbor fetches upstream and caches.

SOURCE="${SOURCE:-github}"     # github|prime
RKE2_VERSION="${RKE2_VERSION:-}"

# Derive RKE2 version tag if not provided
if [[ -z "$RKE2_VERSION" ]]; then
  if command -v rke2 >/dev/null 2>&1; then
    # e.g. "rke2 version v1.31.6+rke2r1"
    RKE2_VERSION="$(rke2 --version 2>/dev/null | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+\+rke2r[0-9]+' | head -n1 || true)"
  fi
fi

if [[ -z "$RKE2_VERSION" ]]; then
  echo "[ERROR] RKE2_VERSION not detected. Set RKE2_VERSION=vX.Y.Z+rke2rN and retry."
  exit 1
fi

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) IMGARCH="amd64" ;;
  aarch64|arm64) IMGARCH="arm64" ;;
  *) IMGARCH="amd64" ;;
esac

CRICTL="/var/lib/rancher/rke2/bin/crictl"
CRICTL_CFG="/var/lib/rancher/rke2/agent/etc/crictl.yaml"

if [[ ! -x "$CRICTL" ]] || [[ ! -f "$CRICTL_CFG" ]]; then
  echo "[ERROR] crictl or CRI config not found. Is RKE2 installed and running?"
  echo "  expected: $CRICTL"
  echo "  expected: $CRICTL_CFG"
  exit 1
fi

export CRI_CONFIG_FILE="$CRICTL_CFG"
LIST_FILE="/var/lib/rancher/rke2/agent/images/00-rke2-system-images-${IMGARCH}.txt"
MARKER="/var/lib/rancher/rke2/agent/images/.prefetch_done_${RKE2_VERSION}"

mkdir -p /var/lib/rancher/rke2/agent/images

if [[ -f "$MARKER" ]]; then
  echo "[INFO] Prefetch already done ($MARKER). Delete marker to re-run."
  exit 0
fi

if [[ "$SOURCE" == "prime" ]]; then
  PRIMARY_URL="https://prime.ribs.rancher.io/rke2/${RKE2_VERSION}/rke2-images.linux-${IMGARCH}.txt"
  FALLBACK_URL="https://github.com/rancher/rke2/releases/download/${RKE2_VERSION}/rke2-images.linux-${IMGARCH}.txt"
else
  PRIMARY_URL="https://github.com/rancher/rke2/releases/download/${RKE2_VERSION}/rke2-images.linux-${IMGARCH}.txt"
  FALLBACK_URL="https://prime.ribs.rancher.io/rke2/${RKE2_VERSION}/rke2-images.linux-${IMGARCH}.txt"
fi

echo "[INFO] Downloading image list for $RKE2_VERSION ($IMGARCH)"
echo "  primary:  $PRIMARY_URL"
if ! curl -fsSL "$PRIMARY_URL" -o "$LIST_FILE"; then
  echo "[WARN] primary failed; trying fallback: $FALLBACK_URL"
  curl -fsSL "$FALLBACK_URL" -o "$LIST_FILE"
fi

sed -i '/^\s*$/d' "$LIST_FILE"
sed -i '/^\s*#/d' "$LIST_FILE"

echo "[INFO] Pulling images via CRI (this will populate Harbor proxy cache if registries.yaml is set)"
FAIL=0
while read -r IMG; do
  [[ -z "$IMG" ]] && continue
  echo "[pull] $IMG"
  "$CRICTL" pull "$IMG" || FAIL=1
done < "$LIST_FILE"

touch "$MARKER"

if [[ "$FAIL" == "0" ]]; then
  echo "[OK] Prefetch completed. Harbor proxy-cache projects should now show cached repos/images."
else
  echo "[WARN] Prefetch completed with errors. Some images may not have been cached."
  exit 2
fi
