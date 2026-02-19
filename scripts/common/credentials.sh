#!/bin/bash
# =============================================================================
# Platform Credentials Discovery
# =============================================================================
# Primary: terraform output (no kubectl required)
# Fallback: kubectl direct secret lookup
#
# 사용법:
#   make credentials         # 조회 방법만 표시
#   make credentials-show    # 실제 비밀번호 표시
# =============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logging.sh"

# ─── Configuration ──────────────────────────────────────────────────────────

SHOW_VALUES=false
[[ "${1:-}" == "--show" ]] && SHOW_VALUES=true

BOOTSTRAP_DIR="${SCRIPT_DIR}/../../stacks/dev/55-bootstrap"

# ─── terraform output (Primary) ────────────────────────────────────────────

_try_terraform_output() {
  if [[ ! -d "$BOOTSTRAP_DIR" ]]; then
    return 1
  fi

  local tf_output
  tf_output=$(cd "$BOOTSTRAP_DIR" && terraform output -json platform_credentials 2>/dev/null) || return 1

  if [[ -z "$tf_output" || "$tf_output" == "null" ]]; then
    return 1
  fi

  echo "$tf_output"
}

_get_tf_value() {
  local json="$1" key="$2"
  echo "$json" | jq -r ".$key // empty" 2>/dev/null
}

# ─── kubectl (Fallback) ────────────────────────────────────────────────────

_check_kubectl() {
  command -v kubectl &>/dev/null && kubectl cluster-info &>/dev/null 2>&1
}

_get_secret() {
  local ns="$1" name="$2" key="$3"
  kubectl get secret "$name" -n "$ns" \
    -o jsonpath="{.data.${key}}" 2>/dev/null | base64 -d 2>/dev/null
}

_secret_exists() {
  local ns="$1" name="$2"
  kubectl get secret "$name" -n "$ns" &>/dev/null 2>&1
}

# ─── Display ────────────────────────────────────────────────────────────────

_print_banner() {
  local source="$1"
  echo ""
  echo -e "${COLOR_BOLD}${COLOR_CYAN}"
  echo "  ╔══════════════════════════════════════════════════════════════╗"
  echo "  ║           🔐  Platform Initial Credentials                 ║"
  echo "  ╚══════════════════════════════════════════════════════════════╝"
  echo -e "${COLOR_NC}"
  echo -e "  ${COLOR_DIM}Source: ${source}${COLOR_NC}"
  echo ""
}

_print_row() {
  local status="$1" service="$2" user="$3" secret_info="$4"
  printf "  ${status} %-12s │ %-22s │ %s\n" "$service" "$user" "$secret_info"
}

_print_separator() {
  echo "  ──────────────┼────────────────────────┼──────────────────────────"
}

_print_table_header() {
  echo -e "  ${COLOR_BOLD}Service        │ Username               │ Password${COLOR_NC}"
  _print_separator
}

_print_footer() {
  echo ""
  echo -e "  ${COLOR_DIM}──────────────────────────────────────────────────────────────${COLOR_NC}"
  if [[ "$SHOW_VALUES" == false ]]; then
    echo -e "  ${COLOR_DIM}💡 Run with ${COLOR_NC}${COLOR_BOLD}make credentials-show${COLOR_NC}${COLOR_DIM} to display actual passwords${COLOR_NC}"
  fi
  echo -e "  ${COLOR_YELLOW}⚠  Change all default passwords immediately after first login${COLOR_NC}"
  echo -e "  ${COLOR_DIM}📖 Full guide: docs/guides/post-deployment-operations-guide.md${COLOR_NC}"
  echo ""
}

# ─── Main: terraform output (Primary) ──────────────────────────────────────

_show_via_terraform() {
  local tf_json="$1"
  _print_banner "terraform output -json platform_credentials"
  _print_table_header

  # 서비스 목록: service|tf_key|username
  local services="argocd|argocd_admin_password|admin
keycloak|keycloak_admin_password|admin
grafana|grafana_admin_password|admin
rancher|rancher_bootstrap|admin
harbor|harbor_default|admin"

  echo "$services" | while IFS='|' read -r svc tf_key username; do
    local value
    value=$(_get_tf_value "$tf_json" "$tf_key")

    if [[ -n "$value" && "$value" != "(not yet available)" && "$value" != "(vault operator init"* ]]; then
      if [[ "$SHOW_VALUES" == true ]]; then
        _print_row "✅" "$svc" "$username" "$value"
      else
        _print_row "✅" "$svc" "$username" "(available — use --show)"
      fi
    else
      _print_row "⚠️ " "$svc" "$username" "(not yet available)"
    fi
  done

  _print_separator

  # Vault root token (항상 수동)
  _print_row "🔑" "vault" "root" "(vault operator init 결과에서 확인)"

  # AIPP (하드코딩)
  if [[ "$SHOW_VALUES" == true ]]; then
    _print_row "🔴" "aipp" "admin@en-core.com" "Admin1234! ← CHANGE IMMEDIATELY"
  else
    _print_row "🔴" "aipp" "admin@en-core.com" "(hardcoded default — CHANGE IMMEDIATELY)"
  fi

  _print_footer
}

# ─── Main: kubectl (Fallback) ──────────────────────────────────────────────

_show_via_kubectl() {
  _print_banner "kubectl (fallback)"
  _print_table_header

  # 서비스 목록: service|namespace|secret_name|key|username
  local services="argocd|argocd|argocd-initial-admin-secret|password|admin
keycloak|keycloak|keycloak-admin-secret|KEYCLOAK_ADMIN_PASSWORD|admin
grafana|monitoring|monitoring-grafana-secret|admin-password|admin
rancher|cattle-system|bootstrap-secret|bootstrapPassword|admin"

  echo "$services" | while IFS='|' read -r svc ns secret_name key username; do
    if _secret_exists "$ns" "$secret_name"; then
      if [[ "$SHOW_VALUES" == true ]]; then
        local pw
        pw=$(_get_secret "$ns" "$secret_name" "$key")
        _print_row "✅" "$svc" "$username" "$pw"
      else
        _print_row "✅" "$svc" "$username" "kubectl get secret ${secret_name} -n ${ns} -o jsonpath='{.data.${key}}' | base64 -d"
      fi
    else
      _print_row "⚠️ " "$svc" "$username" "(secret not found)"
    fi
  done

  _print_separator

  # Vault, Harbor, AIPP (하드코딩)
  if [[ "$SHOW_VALUES" == true ]]; then
    _print_row "🔑" "vault" "root" "(vault operator init 결과에서 확인)"
    _print_row "🔴" "harbor" "admin" "Harbor12345 ← CHANGE IMMEDIATELY"
    _print_row "🔴" "aipp" "admin@en-core.com" "Admin1234! ← CHANGE IMMEDIATELY"
  else
    _print_row "🔑" "vault" "root" "(vault operator init 결과에서 확인)"
    _print_row "🔴" "harbor" "admin" "(hardcoded default — CHANGE IMMEDIATELY)"
    _print_row "🔴" "aipp" "admin@en-core.com" "(hardcoded default — CHANGE IMMEDIATELY)"
  fi

  _print_footer
}

# ─── Entrypoint ─────────────────────────────────────────────────────────────

main() {
  # Strategy: terraform output first, kubectl fallback
  local tf_json
  if tf_json=$(_try_terraform_output); then
    _show_via_terraform "$tf_json"
  elif _check_kubectl; then
    warn "terraform output unavailable — falling back to kubectl"
    _show_via_kubectl
  else
    echo ""
    err "크리덴셜 조회 소스를 찾을 수 없습니다."
    echo ""
    echo "  방법 1) terraform output (AWS 자격증명 필요):"
    echo "         aws-vault exec <profile> -- make credentials"
    echo ""
    echo "  방법 2) kubectl (kubeconfig + 클러스터 접근 필요):"
    echo "         export KUBECONFIG=~/.kube/config-rke2-dev"
    echo "         make credentials"
    echo ""
    exit 1
  fi
}

main "$@"
