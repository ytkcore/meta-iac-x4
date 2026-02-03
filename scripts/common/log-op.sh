#!/bin/bash
# Usage: ./log-op.sh <OP> <STACK> <ENV>
OP=$1
STACK=$2
ENV=$3

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${ROOT_DIR}/scripts/common/logging.sh"

checkpoint "Terraform ${OP} started for STACK=${STACK} (ENV=${ENV})"
