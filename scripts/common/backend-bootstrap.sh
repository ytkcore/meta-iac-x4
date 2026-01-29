#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOT_DIR="${ROOT_DIR}/stacks/bootstrap-backend"

STATE_BUCKET="${STATE_BUCKET:?STATE_BUCKET is required}"
STATE_REGION="${STATE_REGION:-ap-northeast-2}"

tf() {
  terraform -chdir="${BOOT_DIR}" "$@"
}

echo "==> [bootstrap] init (${STATE_BUCKET} / ${STATE_REGION})"
tf init -upgrade=false -reconfigure >/dev/null

# If the bucket already exists (and you have access), import it into bootstrap state
if aws s3api head-bucket --bucket "${STATE_BUCKET}" >/dev/null 2>&1; then
  echo "==> [bootstrap] bucket already exists. Importing into terraform state (if needed)"
  addrs=(
    "aws_s3_bucket.tfstate"
    "aws_s3_bucket_versioning.this"
    "aws_s3_bucket_public_access_block.this"
    "aws_s3_bucket_server_side_encryption_configuration.this"
    "aws_s3_bucket_policy.tls_only"
  )

  for addr in "${addrs[@]}"; do
    if ! tf state list 2>/dev/null | grep -q "^${addr}$"; then
      echo "  - import ${addr}"
      # 일부 리소스(예: policy)는 아직 없을 수 있어 import 실패 가능 -> apply에서 생성됨
      tf import         -var="state_bucket=${STATE_BUCKET}"         -var="state_region=${STATE_REGION}"         "${addr}" "${STATE_BUCKET}" >/dev/null 2>&1 || true
    fi
  done
else
  echo "==> [bootstrap] bucket does not exist. It will be created by terraform."
fi

echo "==> [bootstrap] apply"
tf apply -auto-approve   -var="state_bucket=${STATE_BUCKET}"   -var="state_region=${STATE_REGION}"
