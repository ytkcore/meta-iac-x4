#!/bin/bash
# ==============================================================================
# Keycloak Realm & Client Configuration
#
# Keycloak Admin API를 통해 platform Realm과 5개 서비스 Client를 자동 생성
#
# Usage:
#   ./scripts/keycloak/configure-realm.sh
#
# Prerequisites:
#   - 25-keycloak 스택 배포 완료
#   - Keycloak 접근 가능 (SSM 포트포워딩 또는 VPC 내부)
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
BASE_DOMAIN="${BASE_DOMAIN:-unifiedmeta.net}"
KEYCLOAK_HOST="${KEYCLOAK_HOST:-keycloak.${ENV}.${BASE_DOMAIN}}"
KEYCLOAK_URL="https://${KEYCLOAK_HOST}:8443"
KEYCLOAK_ADMIN="${KEYCLOAK_ADMIN:-admin}"
KEYCLOAK_ADMIN_PASS="${KEYCLOAK_ADMIN_PASS:-}"
REALM_NAME="platform"

# Service redirect URIs
GRAFANA_URL="https://grafana.${BASE_DOMAIN}"
ARGOCD_URL="https://argocd.${BASE_DOMAIN}"
RANCHER_URL="https://rancher.${BASE_DOMAIN}"
HARBOR_URL="https://harbor.${BASE_DOMAIN}"
TELEPORT_URL="https://teleport.${BASE_DOMAIN}"


header "Keycloak Realm & Client 설정"

# ==============================================================================
# 0. Pre-checks
# ==============================================================================

if [[ -z "$KEYCLOAK_ADMIN_PASS" ]]; then
  err "KEYCLOAK_ADMIN_PASS 환경변수가 필요합니다."
  echo "  export KEYCLOAK_ADMIN_PASS='your-admin-password'"
  exit 1
fi

info "Keycloak 주소: ${KEYCLOAK_URL}"
info "Realm 이름: ${REALM_NAME}"

# ==============================================================================
# 1. Get Admin Token
# ==============================================================================

header "Keycloak Admin API 인증 중..."

TOKEN=$(curl -sk -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=${KEYCLOAK_ADMIN}" \
  -d "password=${KEYCLOAK_ADMIN_PASS}" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)

if [[ -z "$TOKEN" ]]; then
  err "Admin 인증 실패. Keycloak이 실행 중인지 확인하세요."
  info "SSM 포트포워딩: aws ssm start-session --target <instance-id> --document-name AWS-StartPortForwardingSession --parameters portNumber=8443,localPortNumber=8443"
  exit 1
fi
ok "Admin 토큰 획득 성공"

AUTH_HEADER="Authorization: Bearer ${TOKEN}"

# ==============================================================================
# 2. Create Realm (if not exists)
# ==============================================================================

header "Realm 생성: ${REALM_NAME}"

EXISTING_REALM=$(curl -sk -o /dev/null -w "%{http_code}" \
  -H "${AUTH_HEADER}" \
  "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}")

if [[ "$EXISTING_REALM" == "200" ]]; then
  ok "Realm '${REALM_NAME}' 이미 존재함"
else
  curl -sk -X POST "${KEYCLOAK_URL}/admin/realms" \
    -H "${AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    -d "{
      \"realm\": \"${REALM_NAME}\",
      \"enabled\": true,
      \"displayName\": \"Platform SSO\",
      \"sslRequired\": \"external\",
      \"registrationAllowed\": false,
      \"loginWithEmailAllowed\": true,
      \"duplicateEmailsAllowed\": false,
      \"resetPasswordAllowed\": true,
      \"editUsernameAllowed\": false,
      \"bruteForceProtected\": true
    }" && ok "Realm '${REALM_NAME}' 생성 완료" || err "Realm 생성 실패"
fi

# ==============================================================================
# 3. Create Groups
# ==============================================================================

header "그룹 생성 중..."

for GROUP in admin editor developer viewer; do
  curl -sk -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/groups" \
    -H "${AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"${GROUP}\"}" 2>/dev/null && ok "그룹 '${GROUP}' 생성됨" || info "그룹 '${GROUP}' 이미 존재할 수 있음"
done

# ==============================================================================
# 4. Create OIDC Clients
# ==============================================================================

create_client() {
  local CLIENT_ID="$1"
  local REDIRECT_URI="$2"
  local CLIENT_NAME="$3"

  info "Client 생성: ${CLIENT_ID}..."

  # Generate a client secret
  local CLIENT_SECRET
  CLIENT_SECRET=$(openssl rand -hex 16)

  curl -sk -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients" \
    -H "${AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    -d "{
      \"clientId\": \"${CLIENT_ID}\",
      \"name\": \"${CLIENT_NAME}\",
      \"enabled\": true,
      \"protocol\": \"openid-connect\",
      \"publicClient\": false,
      \"secret\": \"${CLIENT_SECRET}\",
      \"standardFlowEnabled\": true,
      \"directAccessGrantsEnabled\": false,
      \"serviceAccountsEnabled\": false,
      \"redirectUris\": [\"${REDIRECT_URI}/*\"],
      \"webOrigins\": [\"${REDIRECT_URI}\"],
      \"attributes\": {
        \"post.logout.redirect.uris\": \"${REDIRECT_URI}/*\"
      },
      \"defaultClientScopes\": [\"openid\", \"email\", \"profile\", \"roles\"],
      \"protocolMappers\": [{
        \"name\": \"groups\",
        \"protocol\": \"openid-connect\",
        \"protocolMapper\": \"oidc-group-membership-mapper\",
        \"config\": {
          \"full.path\": \"false\",
          \"id.token.claim\": \"true\",
          \"access.token.claim\": \"true\",
          \"claim.name\": \"groups\",
          \"userinfo.token.claim\": \"true\"
        }
      }]
    }" && ok "Client '${CLIENT_ID}' 생성 완료 (secret: ${CLIENT_SECRET})" \
       || warn "Client '${CLIENT_ID}' 이미 존재할 수 있음"

  echo "  ${CLIENT_ID}_SECRET=${CLIENT_SECRET}" >> "${SCRIPT_DIR}/client-secrets.env"
}

header "OIDC 클라이언트 생성 중..."
rm -f "${SCRIPT_DIR}/client-secrets.env"
touch "${SCRIPT_DIR}/client-secrets.env"

create_client "grafana"  "${GRAFANA_URL}"  "Grafana Observability"
create_client "argocd"   "${ARGOCD_URL}"   "ArgoCD GitOps"
create_client "rancher"  "${RANCHER_URL}"  "Rancher Management"
create_client "harbor"   "${HARBOR_URL}"   "Harbor Registry"
create_client "teleport" "${TELEPORT_URL}" "Teleport Access"

# ==============================================================================
# 5. Create Admin User
# ==============================================================================

header "플랫폼 관리자 사용자 생성 중..."

ADMIN_EMAIL="${ADMIN_EMAIL:-admin@${BASE_DOMAIN}}"
ADMIN_TEMP_PASS="${ADMIN_TEMP_PASS:-PlatformAdmin1234!}"

curl -sk -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users" \
  -H "${AUTH_HEADER}" \
  -H "Content-Type: application/json" \
  -d "{
    \"username\": \"platform-admin\",
    \"email\": \"${ADMIN_EMAIL}\",
    \"emailVerified\": true,
    \"enabled\": true,
    \"groups\": [\"admin\"],
    \"credentials\": [{
      \"type\": \"password\",
      \"value\": \"${ADMIN_TEMP_PASS}\",
      \"temporary\": true
    }]
  }" && ok "관리자 사용자 생성 완료 (비밀번호: ${ADMIN_TEMP_PASS}, 초기 로그인 시 변경 필요)" \
     || warn "관리자 사용자가 이미 존재할 수 있음"

# ==============================================================================
# Summary
# ==============================================================================

checkpoint "Keycloak 설정 완료"
echo ""
echo "  Realm:     ${REALM_NAME}"
echo "  Clients:   grafana, argocd, rancher, harbor, teleport"
echo "  Admin:     platform-admin / ${ADMIN_TEMP_PASS} (임시)"
echo ""
echo "  Client secrets 저장 위치: ${SCRIPT_DIR}/client-secrets.env"
echo ""
warn "client-secrets.env 파일을 안전한 곳에 보관 후 삭제하세요."
info "다음 단계: ./scripts/keycloak/patch-albc-vpcid.sh"
