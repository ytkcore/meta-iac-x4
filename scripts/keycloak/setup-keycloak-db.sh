#!/bin/bash
# ==============================================================================
# Keycloak PostgreSQL Database Setup
#
# 60-postgres 인스턴스에 SSM 경유로 Keycloak 전용 DB/User 생성
#
# Usage:
#   ./scripts/keycloak/setup-keycloak-db.sh
#
# Prerequisites:
#   - 60-postgres 스택 배포 완료
#   - aws-vault / SSM 접근 가능
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=../common/logging.sh
source "${PROJECT_ROOT}/scripts/common/logging.sh"

# ==============================================================================
# Config
# ==============================================================================

ENV="${ENV:-dev}"
KEYCLOAK_DB_NAME="${KEYCLOAK_DB_NAME:-keycloak}"
KEYCLOAK_DB_USER="${KEYCLOAK_DB_USER:-keycloak}"
KEYCLOAK_DB_PASS="${KEYCLOAK_DB_PASS:-}"

header "Keycloak PostgreSQL Database Setup"

# ==============================================================================
# 1. Get Postgres Instance ID from Terraform output
# ==============================================================================

info "Fetching PostgreSQL instance ID from 60-postgres stack..."

POSTGRES_INSTANCE_ID=$(cd "${PROJECT_ROOT}/stacks/${ENV}/60-postgres" && \
  terraform output -raw instance_id 2>/dev/null || echo "")

if [[ -z "$POSTGRES_INSTANCE_ID" ]]; then
  err "60-postgres instance_id not found. Is the stack deployed?"
  exit 1
fi
ok "PostgreSQL instance: ${POSTGRES_INSTANCE_ID}"

# ==============================================================================
# 2. Generate password if not provided
# ==============================================================================

if [[ -z "$KEYCLOAK_DB_PASS" ]]; then
  KEYCLOAK_DB_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 20)
  warn "Generated random password: ${KEYCLOAK_DB_PASS}"
  warn "이 비밀번호를 안전한 곳에 저장하세요!"
fi

# ==============================================================================
# 3. Create database and user via SSM
# ==============================================================================

header "Creating Keycloak database and user via SSM..."

SQL_COMMANDS=$(cat <<EOF
-- Create Keycloak user (if not exists)
DO \\\$\\\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${KEYCLOAK_DB_USER}') THEN
    CREATE ROLE ${KEYCLOAK_DB_USER} WITH LOGIN PASSWORD '${KEYCLOAK_DB_PASS}';
    RAISE NOTICE 'User ${KEYCLOAK_DB_USER} created';
  ELSE
    ALTER ROLE ${KEYCLOAK_DB_USER} WITH PASSWORD '${KEYCLOAK_DB_PASS}';
    RAISE NOTICE 'User ${KEYCLOAK_DB_USER} password updated';
  END IF;
END
\\\$\\\$;

-- Create Keycloak database (if not exists)
SELECT 'CREATE DATABASE ${KEYCLOAK_DB_NAME} OWNER ${KEYCLOAK_DB_USER}'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${KEYCLOAK_DB_NAME}');

-- Grant permissions
GRANT ALL PRIVILEGES ON DATABASE ${KEYCLOAK_DB_NAME} TO ${KEYCLOAK_DB_USER};
EOF
)

info "Executing SQL via SSM..."
aws ssm send-command \
  --instance-ids "${POSTGRES_INSTANCE_ID}" \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[\"sudo -u postgres psql -c \\\"${SQL_COMMANDS}\\\"\"]" \
  --output text \
  --query "Command.CommandId" 2>/dev/null && ok "SQL commands sent" || {
    warn "SSM 명령 전송 실패. 수동 실행 필요:"
    echo ""
    echo "  aws ssm start-session --target ${POSTGRES_INSTANCE_ID}"
    echo "  sudo -u postgres psql"
    echo "  CREATE USER ${KEYCLOAK_DB_USER} WITH PASSWORD '${KEYCLOAK_DB_PASS}';"
    echo "  CREATE DATABASE ${KEYCLOAK_DB_NAME} OWNER ${KEYCLOAK_DB_USER};"
    echo ""
  }

# ==============================================================================
# 4. Summary
# ==============================================================================

checkpoint "Keycloak DB Setup Complete"
echo ""
echo "  DB Host:     (60-postgres private IP)"
echo "  DB Port:     5432"
echo "  DB Name:     ${KEYCLOAK_DB_NAME}"
echo "  DB User:     ${KEYCLOAK_DB_USER}"
echo "  DB Password: ${KEYCLOAK_DB_PASS}"
echo ""
info "다음 단계: ./scripts/keycloak/configure-realm.sh"
