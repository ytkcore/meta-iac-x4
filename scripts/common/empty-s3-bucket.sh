#!/bin/bash
# =============================================================================
# Empty S3 Bucket Script
# Usage: ./empty-s3-bucket.sh <bucket-name>
# =============================================================================

set -uo pipefail

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
GREEN=$'\e[32m'
RED=$'\e[31m'
YELLOW=$'\e[33m'
CYAN=$'\e[36m'
DIM=$'\e[2m'
NC=$'\e[0m'

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------
ok()     { echo -e "  ${GREEN}✓${NC} $*"; }
fail()   { echo -e "  ${RED}✗${NC} $*"; }
warn()   { echo -e "  ${YELLOW}!${NC} $*"; }
info()   { echo -e "  ${DIM}$*${NC}"; }
header() { echo -e "\n${CYAN}[$1]${NC} $2"; }

add_item() {
  local key="$1" vid="$2"
  if [[ ${COUNT} -gt 0 ]]; then JSON+=','; fi
  JSON+="{\"Key\":\"${key}\",\"VersionId\":\"${vid}\"}"
  COUNT=$((COUNT+1))
}

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------
BUCKET="${1:-}"
if [[ -z "${BUCKET}" ]]; then
  echo "Usage: $0 <bucket-name>"
  exit 2
fi

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
header 1 "Emptying s3://${BUCKET}"

info "Removing objects..."
aws s3 rm "s3://${BUCKET}" --recursive || true

header 2 "Cleaning Versions & Delete Markers"
while true; do
  VERS=$(aws s3api list-object-versions --bucket "${BUCKET}" \
    --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null || true)
  MARK=$(aws s3api list-object-versions --bucket "${BUCKET}" \
    --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null || true)

  [[ -z "${VERS}" && -z "${MARK}" ]] && break

  JSON='{"Objects":['
  COUNT=0

  if [[ -n "${VERS}" ]]; then
    while read -r key vid rest; do
      [[ -z "${key}" || -z "${vid}" ]] && continue
      add_item "${key}" "${vid}"
      [[ ${COUNT} -ge 1000 ]] && break
    done <<< "${VERS}"
  fi

  if [[ ${COUNT} -lt 1000 && -n "${MARK}" ]]; then
    while read -r key vid rest; do
      [[ -z "${key}" || -z "${vid}" ]] && continue
      add_item "${key}" "${vid}"
      [[ ${COUNT} -ge 1000 ]] && break
    done <<< "${MARK}"
  fi

  JSON+='],"Quiet":true}'
  [[ ${COUNT} -eq 0 ]] && break

  info "Deleting ${COUNT} versions..."
  aws s3api delete-objects --bucket "${BUCKET}" --delete "${JSON}" >/dev/null 2>&1 || true
done

ok "Bucket emptied successfully"
