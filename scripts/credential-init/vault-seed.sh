#!/bin/bash
# =============================================================================
# Vault Credential Init — Phase 2/3 (90-credential-init)
# =============================================================================
# Vault에 ESO 인프라 + OIDC Client Secret을 사전 저장
#
# 사전 조건:
#   - Vault가 Unseal 상태
#   - VAULT_ADDR, VAULT_TOKEN 환경변수 설정
#
# 사용법:
#   export VAULT_ADDR="https://vault.dev.unifiedmeta.net"
#   export VAULT_TOKEN="<root-token>"
#   ./vault-seed.sh
# =============================================================================

set -euo pipefail

# ─── Pre-flight ─────────────────────────────────────────────────────────────

if [[ -z "${VAULT_ADDR:-}" ]]; then
  echo "❌ VAULT_ADDR not set"
  echo "   export VAULT_ADDR='https://vault.dev.unifiedmeta.net'"
  exit 1
fi

if [[ -z "${VAULT_TOKEN:-}" ]]; then
  echo "❌ VAULT_TOKEN not set"
  echo "   export VAULT_TOKEN='<root-token>'"
  exit 1
fi

echo "🔐 Vault: ${VAULT_ADDR}"
echo ""

# ─── Phase 2: ESO 인프라 설정 ──────────────────────────────────────────────

echo "═══ Phase 2: ESO 인프라 설정 ═══"
echo ""

# KV Secrets Engine 활성화 (이미 있으면 skip)
echo "→ KV v2 Secrets Engine 확인..."
vault secrets enable -path=secret kv-v2 2>/dev/null && echo "  ✅ secret/ 활성화" || echo "  ℹ️  secret/ 이미 존재"

# K8s Auth Method 활성화
echo "→ K8s Auth Method 확인..."
vault auth enable kubernetes 2>/dev/null && echo "  ✅ kubernetes auth 활성화" || echo "  ℹ️  kubernetes auth 이미 존재"

# K8s Auth 설정 (클러스터 내부에서 실행 시)
echo "→ K8s Auth 설정..."
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443" 2>/dev/null \
  && echo "  ✅ kubernetes auth config 설정 완료" \
  || echo "  ⚠️  kubernetes auth config 설정 실패 (클러스터 외부에서 실행 중일 수 있음)"

# ESO용 Policy
echo "→ platform-read Policy 생성..."
vault policy write platform-read - <<EOF
# ESO가 Vault에서 플랫폼 Secret을 읽을 수 있는 정책
path "secret/data/platform/*" {
  capabilities = ["read"]
}
path "secret/metadata/platform/*" {
  capabilities = ["read", "list"]
}
EOF
echo "  ✅ platform-read 정책 생성 완료"

# ESO용 K8s Auth Role
echo "→ external-secrets Role 생성..."
vault write auth/kubernetes/role/external-secrets \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=platform-read \
  ttl=1h
echo "  ✅ external-secrets Role 생성 완료"

echo ""

# ─── Phase 3: OIDC Client Secret 저장 ──────────────────────────────────────

echo "═══ Phase 3: OIDC Client Secret 저장 ═══"
echo ""
echo "ℹ️  Keycloak에서 OIDC Client를 먼저 생성한 후, 아래 명령어로 Secret을 저장하세요:"
echo ""
echo "  vault kv put secret/platform/oidc/argocd \\"
echo "    client-id=argocd \\"
echo "    client-secret=<ARGOCD_CLIENT_SECRET>"
echo ""
echo "  vault kv put secret/platform/oidc/grafana \\"
echo "    client-id=grafana \\"
echo "    client-secret=<GRAFANA_CLIENT_SECRET>"
echo ""
echo "  vault kv put secret/platform/oidc/harbor \\"
echo "    client-id=harbor \\"
echo "    client-secret=<HARBOR_CLIENT_SECRET>"
echo ""
echo "  vault kv put secret/platform/oidc/rancher \\"
echo "    client-id=rancher \\"
echo "    client-secret=<RANCHER_CLIENT_SECRET>"
echo ""

echo "═══ 완료 ═══"
echo ""
echo "다음 단계:"
echo "  1. git push (ESO + ClusterSecretStore ArgoCD sync)"
echo "  2. Keycloak OIDC Client 생성"
echo "  3. 위 vault kv put 명령어 실행"
echo "  4. ExternalSecret YAML git push"
echo ""
