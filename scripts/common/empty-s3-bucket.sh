#!/usr/bin/env bash
set -euo pipefail

# Empty an S3 bucket including versions/delete-markers (no jq).
# Usage:
#   ./scripts/empty-s3-bucket.sh <bucket-name>
# With aws-vault:
#   aws-vault exec <profile> -- ./scripts/empty-s3-bucket.sh <bucket-name>

BUCKET="${1:-}"
if [[ -z "${BUCKET}" ]]; then
  echo "Usage: $0 <bucket-name>"
  exit 2
fi

echo "Emptying s3://${BUCKET} ..."

aws s3 rm "s3://${BUCKET}" --recursive || true

while true; do
  VERS=$(aws s3api list-object-versions --bucket "${BUCKET}" --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null || true)
  MARK=$(aws s3api list-object-versions --bucket "${BUCKET}" --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null || true)

  [[ -z "${VERS}" && -z "${MARK}" ]] && break

  JSON='{"Objects":['
  COUNT=0

  add_item () {
    local key="$1"; local vid="$2"
    if [[ ${COUNT} -gt 0 ]]; then JSON+=','; fi
    JSON+="{"Key":"${key}","VersionId":"${vid}"}"
    COUNT=$((COUNT+1))
  }

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

  aws s3api delete-objects --bucket "${BUCKET}" --delete "${JSON}" >/dev/null 2>&1 || true
done

echo "Done."
