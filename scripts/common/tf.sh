#!/usr/bin/env bash
set -euo pipefail

# Terraform wrapper (hides -chdir complexity).
# Usage:
#   ./scripts/tf.sh <env> <stack> <cmd> [args...]
# Examples:
#   ./scripts/tf.sh dev 00-network plan
#   ./scripts/tf.sh dev 10-security apply -auto-approve
#
# With aws-vault:
#   aws-vault exec <profile> -- ./scripts/tf.sh dev 00-network plan
# Or:
#   VAULT_PROFILE=<profile> ./scripts/tf.sh dev 00-network plan

ENV="${1:-}"
STACK="${2:-}"
CMD="${3:-}"
shift 3 || true

if [[ -z "${ENV}" || -z "${STACK}" || -z "${CMD}" ]]; then
  echo "Usage: $0 <env> <stack> <cmd> [args...]"
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_DIR="${ROOT_DIR}/stacks/${ENV}/${STACK}"

if [[ ! -d "${STACK_DIR}" ]]; then
  echo "Stack dir not found: ${STACK_DIR}"
  exit 2
fi

STATE_REGION="${STATE_REGION:-ap-northeast-2}"
STATE_BUCKET="${STATE_BUCKET:-enc-tfstate}"
STATE_KEY_PREFIX="${STATE_KEY_PREFIX:-enc-iac}"

TF_RUN=()
if [[ -n "${VAULT_PROFILE:-}" ]]; then
  if [[ -n "${VAULT_DURATION:-}" ]]; then
    TF_RUN=(aws-vault exec "${VAULT_PROFILE}" --duration="${VAULT_DURATION}" --)
  else
    TF_RUN=(aws-vault exec "${VAULT_PROFILE}" --)
  fi
fi

# Auto-init when it likely needs a backend/provider
if [[ "${CMD}" =~ ^(plan|apply|destroy|refresh|output|show|validate)$ ]]; then
  "${TF_RUN[@]}" terraform -chdir="${STACK_DIR}" init -upgrade=false     -backend-config="bucket=${STATE_BUCKET}"     -backend-config="key=${STATE_KEY_PREFIX}/${ENV}/${STACK}.tfstate"     -backend-config="region=${STATE_REGION}"     -backend-config="encrypt=true"     -backend-config="use_lockfile=true" >/dev/null
fi

exec "${TF_RUN[@]}" terraform -chdir="${STACK_DIR}" "${CMD}" "$@"
