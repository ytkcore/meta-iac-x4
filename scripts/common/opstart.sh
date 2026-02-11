#!/bin/bash
# ==============================================================================
# Post-Deployment Operations Bootstrap
#
# Description:
#   - 배포 후 운영 초기화(Bootstrap)를 위한 CLI 도구입니다.
#   - 6단계 순차 실행: Vault → Secret → Keycloak → ArgoCD → Rancher → Monitoring
#   - 웹 대시보드(β)는 K8s Pod로 별도 배포됩니다.
#
# Usage:
#   make opstart            # 6단계 운영 초기화 (CLI)
#   make opstart-ui         # 웹 대시보드 접속 (kubectl port-forward)
#
# Maintainer: DevOps Team
# ==============================================================================

set -uo pipefail

# ------------------------------------------------------------------------------
# 환경 변수 (Variables)
# ------------------------------------------------------------------------------
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Symbols
SYM_OK="✓"
SYM_FAIL="✕"
SYM_SKIP="○"
SYM_ARROW="▸"
SYM_STEP="▪"

# ==============================================================================
# 6단계 운영 초기화
# ==============================================================================

TOTAL=6
COMPLETED=0
SKIPPED=0
FAILED=0

header() {
    echo ""
    echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}  META PLATFORM — 배포 후 운영 초기화${NC}"
    echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════${NC}"
    echo ""
}

step_header() {
    local num="$1" title="$2" desc="$3"
    echo ""
    echo -e "${BOLD}${SYM_STEP} [${num}/${TOTAL}] ${title}${NC}"
    echo -e "  ${DIM}${desc}${NC}"
}

prompt_run() {
    local msg="${1:-실행하시겠습니까?}"
    echo -ne "  ${YELLOW}${SYM_ARROW} ${msg} [Y/n/s(건너뛰기)] ${NC}"
    read -r ans
    case "${ans,,}" in
        n|no) return 1 ;;
        s|skip) return 2 ;;
        *) return 0 ;;
    esac
}

run_script() {
    local script="$1"
    shift
    local script_path="${PROJECT_ROOT}/${script}"

    if [ ! -f "$script_path" ]; then
        echo -e "  ${RED}${SYM_FAIL} 스크립트를 찾을 수 없습니다: ${script}${NC}"
        return 1
    fi

    chmod +x "$script_path"
    echo -e "  ${DIM}실행 중: ${script}${NC}"

    local output
    output=$("$script_path" "$@" 2>&1)
    local rc=$?

    if [ $rc -eq 0 ]; then
        echo -e "  ${GREEN}${SYM_OK} 완료${NC}"
        if [ -n "$output" ]; then
            echo "$output" | head -5 | while IFS= read -r line; do
                echo -e "    ${DIM}${line}${NC}"
            done
            local linecount
            linecount=$(echo "$output" | wc -l | tr -d ' ')
            if [ "$linecount" -gt 5 ]; then
                echo -e "    ${DIM}... (${linecount}줄 중 5줄 표시)${NC}"
            fi
        fi
        return 0
    else
        echo -e "  ${RED}${SYM_FAIL} 실패 (exit code: ${rc})${NC}"
        if [ -n "$output" ]; then
            echo "$output" | tail -3 | while IFS= read -r line; do
                echo -e "    ${RED}${line}${NC}"
            done
        fi
        return 1
    fi
}

run_step() {
    local num="$1"
    prompt_run
    local ans=$?
    if [ $ans -eq 1 ]; then
        echo -e "  ${DIM}${SYM_SKIP} 중단${NC}"
        return 1
    elif [ $ans -eq 2 ]; then
        echo -e "  ${YELLOW}${SYM_SKIP} 건너뜀${NC}"
        ((SKIPPED++))
        return 0
    fi
    return 3  # proceed
}

# --------------------------------------------------------------------------
header

# --- Step 1: Vault 상태 확인 ---
step_header 1 "Vault 상태 확인" "Vault Unseal 상태 및 클러스터 연결을 확인합니다."
run_step 1
ans=$?
if [ $ans -eq 3 ]; then
    VAULT_NS=$(kubectl get ns vault --no-headers 2>/dev/null | awk '{print $1}')
    if [ -z "$VAULT_NS" ]; then
        echo -e "  ${YELLOW}⚠ Vault Namespace를 찾을 수 없습니다${NC}"
        ((FAILED++))
    else
        VAULT_STATUS=$(kubectl -n vault exec vault-0 -- vault status -format=json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print('active' if not d.get('sealed') else 'sealed')" 2>/dev/null || echo "unknown")
        if [ "$VAULT_STATUS" = "active" ]; then
            echo -e "  ${GREEN}${SYM_OK} Vault 상태: Active (Unsealed)${NC}"
            ((COMPLETED++))
        elif [ "$VAULT_STATUS" = "sealed" ]; then
            echo -e "  ${RED}${SYM_FAIL} Vault 상태: Sealed — Unseal이 필요합니다${NC}"
            ((FAILED++))
        else
            echo -e "  ${YELLOW}⚠ Vault 상태 확인 불가: ${VAULT_STATUS}${NC}"
            ((FAILED++))
        fi
    fi
fi

# --- Step 2: Secret 주입 ---
step_header 2 "Secret 주입" "Keycloak DB/Admin 시크릿을 K8s에 생성합니다."
run_step 2
ans=$?
if [ $ans -eq 3 ]; then
    KC_DB=$(kubectl -n keycloak get secret keycloak-db-secret --no-headers 2>/dev/null)
    KC_ADMIN=$(kubectl -n keycloak get secret keycloak-admin-secret --no-headers 2>/dev/null)
    if [ -n "$KC_DB" ] && [ -n "$KC_ADMIN" ]; then
        echo -e "  ${GREEN}${SYM_OK} Secret이 이미 존재합니다 (건너뜀)${NC}"
        ((COMPLETED++))
    else
        run_script "scripts/keycloak/setup-keycloak-db.sh" && ((COMPLETED++)) || ((FAILED++))
    fi
fi

# --- Step 3: Identity Provider 설정 ---
step_header 3 "Identity Provider 설정" "Keycloak Platform Realm 및 SSO Client를 구성합니다."
run_step 3
ans=$?
if [ $ans -eq 3 ]; then
    run_script "scripts/keycloak/configure-realm.sh" && ((COMPLETED++)) || ((FAILED++))
fi

# --- Step 4: GitOps 동기화 ---
step_header 4 "GitOps 동기화" "ArgoCD 애플리케이션 배포 상태를 확인합니다."
run_step 4
ans=$?
if [ $ans -eq 3 ]; then
    run_script "scripts/argocd/sync-all.sh" && ((COMPLETED++)) || ((FAILED++))
fi

# --- Step 5: Cluster 등록 ---
step_header 5 "Cluster 등록" "Rancher에 클러스터를 등록합니다."
echo -e "  ${YELLOW}ℹ 수동 작업: Rancher UI에서 Import로 클러스터를 등록하세요.${NC}"
echo -e "  ${DIM}  URL: https://rancher.unifiedmeta.net${NC}"
prompt_run "완료하셨습니까?"
ans=$?
if [ $ans -eq 0 ]; then
    echo -e "  ${GREEN}${SYM_OK} 수동 완료 확인${NC}"
    ((COMPLETED++))
elif [ $ans -eq 2 ]; then
    echo -e "  ${YELLOW}${SYM_SKIP} 건너뜀${NC}"
    ((SKIPPED++))
fi

# --- Step 6: Monitoring ---
step_header 6 "Monitoring" "Grafana 대시보드를 확인합니다."
echo -e "  ${YELLOW}ℹ 수동 작업: Grafana에 접속하여 데이터 수집을 확인하세요.${NC}"
echo -e "  ${DIM}  URL: https://grafana.unifiedmeta.net${NC}"
prompt_run "완료하셨습니까?"
ans=$?
if [ $ans -eq 0 ]; then
    echo -e "  ${GREEN}${SYM_OK} 수동 완료 확인${NC}"
    ((COMPLETED++))
elif [ $ans -eq 2 ]; then
    echo -e "  ${YELLOW}${SYM_SKIP} 건너뜀${NC}"
    ((SKIPPED++))
fi

# --------------------------------------------------------------------------
# 최종 결과
# --------------------------------------------------------------------------
echo ""
echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════${NC}"
echo -e "  ${BOLD}결과 요약${NC}"
echo -e "  ${GREEN}${SYM_OK} 완료: ${COMPLETED}${NC}  ${YELLOW}${SYM_SKIP} 건너뜀: ${SKIPPED}${NC}  ${RED}${SYM_FAIL} 실패: ${FAILED}${NC}  /  전체 ${TOTAL}"
echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════${NC}"
echo ""

if [ $FAILED -gt 0 ]; then
    exit 1
fi
exit 0
