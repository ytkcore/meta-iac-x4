#!/bin/bash
# ==============================================================================
# Architecture Evolution — Full Deployment Orchestrator
#
# 5-Phase 아키텍처 고도화 전체 배포를 순서대로 실행
#
# Usage:
#   ./scripts/keycloak/deploy-evolution.sh [phase]
#
# Examples:
#   ./scripts/keycloak/deploy-evolution.sh        # 전체 실행
#   ./scripts/keycloak/deploy-evolution.sh 1      # Phase 1만
#   ./scripts/keycloak/deploy-evolution.sh 2      # Phase 2만
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=../common/logging.sh
source "${PROJECT_ROOT}/scripts/common/logging.sh"

ENV="${ENV:-dev}"
PHASE="${1:-all}"

header "Architecture Evolution Deployment — Phase: ${PHASE}"
echo ""
echo "  Phase 1: ALBC + NLB IP Mode"
echo "  Phase 2: Keycloak SSO"
echo "  Phase 3: OIDC Federation"
echo "  Phase 4: Vault"
echo "  Phase 5: CCM Removal"
echo ""

confirm_proceed() {
  local msg="$1"
  echo ""
  read -rp "$(echo -e "${COLOR_YELLOW}${msg} [y/N]:${COLOR_NC} ")" answer
  [[ "$answer" =~ ^[Yy]$ ]] || { info "Skipped."; return 1; }
}

# ==============================================================================
# Phase 1: ALBC + NLB IP Mode
# ==============================================================================

run_phase_1() {
  header "Phase 1: ALBC + NLB IP Mode"

  info "Step 1.1 — Apply 50-rke2 (ALBC IAM Policy 생성)"
  confirm_proceed "50-rke2 apply?" && {
    cd "${PROJECT_ROOT}/stacks/${ENV}/50-rke2"
    terraform init -backend-config=../backend.hcl
    terraform plan -var-file=../env.tfvars -out=tfplan
    confirm_proceed "Apply plan?" && terraform apply tfplan
    ok "50-rke2 applied"
  }

  info "Step 1.2 — Patch ALBC VPC ID"
  "${SCRIPT_DIR}/patch-albc-vpcid.sh"

  info "Step 1.3 — Git commit & push (ArgoCD auto-sync)"
  confirm_proceed "Git commit changes?" && {
    cd "${PROJECT_ROOT}"
    git add gitops-apps/bootstrap/aws-load-balancer-controller.yaml \
            gitops-apps/bootstrap/nginx-ingress.yaml \
            gitops-apps/bootstrap/nginx-ingress-internal.yaml
    git commit -m "feat: Phase 1 — ALBC + NLB IP mode

- Add AWS Load Balancer Controller ArgoCD App
- Switch nginx-ingress to ALBC IP target mode
- Patch VPC ID for ALBC"
    git push
    ok "Pushed to Git — ArgoCD will auto-sync"
  }

  warn "⚠️  NLB가 재생성됩니다. DNS 전파 시간(~5분) 동안 다운타임 발생 가능."
  checkpoint "Phase 1 Complete"
}

# ==============================================================================
# Phase 2: Keycloak SSO
# ==============================================================================

run_phase_2() {
  header "Phase 2: Keycloak SSO"

  info "Step 2.1 — Setup Keycloak DB on PostgreSQL"
  "${SCRIPT_DIR}/setup-keycloak-db.sh"

  info "Step 2.2 — Apply 25-keycloak (Keycloak EC2 + DNS)"
  confirm_proceed "25-keycloak apply?" && {
    cd "${PROJECT_ROOT}/stacks/${ENV}/25-keycloak"
    terraform init -backend-config=../backend.hcl
    terraform plan -var-file=../env.tfvars -out=tfplan
    confirm_proceed "Apply plan?" && terraform apply tfplan
    ok "25-keycloak applied"
  }

  info "Step 2.3 — Wait for Keycloak to be ready (~90s)"
  KEYCLOAK_INSTANCE_ID=$(cd "${PROJECT_ROOT}/stacks/${ENV}/25-keycloak" && \
    terraform output -raw instance_id 2>/dev/null || echo "")

  if [[ -n "$KEYCLOAK_INSTANCE_ID" ]]; then
    info "Keycloak Instance: ${KEYCLOAK_INSTANCE_ID}"
    info "SSM 포트포워딩 대기중..."
    echo ""
    echo "  별도 터미널에서 실행:"
    echo "  aws ssm start-session --target ${KEYCLOAK_INSTANCE_ID} \\"
    echo "    --document-name AWS-StartPortForwardingSession \\"
    echo "    --parameters portNumber=8443,localPortNumber=8443"
    echo ""
  fi

  confirm_proceed "Keycloak 접근 가능 확인 후 Realm 설정?" && {
    "${SCRIPT_DIR}/configure-realm.sh"
  }

  info "Step 2.4 — Git commit SSO config changes"
  confirm_proceed "Git commit Grafana/ArgoCD OIDC config?" && {
    cd "${PROJECT_ROOT}"
    git add gitops-apps/bootstrap/monitoring.yaml \
            stacks/dev/55-bootstrap/templates/argocd-values.yaml.tftpl
    git commit -m "feat: Phase 2 — Keycloak OIDC SSO integration

- Grafana: generic_oauth with Keycloak
- ArgoCD: OIDC config with group-based RBAC
- Realm: platform (admin/editor/developer/viewer groups)"
    git push
    ok "Pushed to Git"
  }

  checkpoint "Phase 2 Complete"
}

# ==============================================================================
# Phase 3: OIDC Federation
# ==============================================================================

run_phase_3() {
  header "Phase 3: OIDC Federation (Keycloak → AWS IAM)"

  info "Step 3.1 — Enable OIDC Federation"
  confirm_proceed "enable_oidc_federation=true 적용?" && {
    cd "${PROJECT_ROOT}/stacks/${ENV}/25-keycloak"
    terraform init -backend-config=../backend.hcl
    terraform plan -var-file=../env.tfvars -var="enable_oidc_federation=true" -out=tfplan
    confirm_proceed "Apply plan?" && terraform apply tfplan
    ok "OIDC Federation enabled"

    IRSA_ROLE_ARN=$(terraform output -raw albc_irsa_role_arn 2>/dev/null || echo "")
    if [[ -n "$IRSA_ROLE_ARN" ]]; then
      ok "ALBC IRSA Role: ${IRSA_ROLE_ARN}"
      warn "ALBC ArgoCD App의 serviceAccount annotation에 이 ARN을 추가하세요."
    fi
  }

  checkpoint "Phase 3 Complete"
}

# ==============================================================================
# Phase 4: Vault
# ==============================================================================

run_phase_4() {
  header "Phase 4: Vault Deployment"

  info "Step 4.1 — Git commit Vault ArgoCD App"
  confirm_proceed "Vault ArgoCD App push?" && {
    cd "${PROJECT_ROOT}"
    git add gitops-apps/bootstrap/vault.yaml
    git commit -m "feat: Phase 4 — Vault deployment

- HashiCorp Vault ArgoCD App (standalone + Longhorn)
- Sidecar injector enabled
- Internal-only ingress (Teleport access)"
    git push
    ok "Pushed — ArgoCD will deploy Vault"
  }

  echo ""
  warn "Vault 배포 후 수동 구성 필요:"
  echo "  1. vault operator init"
  echo "  2. vault operator unseal (3/5 keys)"
  echo "  3. vault auth enable oidc (Keycloak 연동)"
  echo "  4. vault secrets enable database (PostgreSQL dynamic secrets)"
  echo ""

  checkpoint "Phase 4 Complete"
}

# ==============================================================================
# Phase 5: CCM Removal
# ==============================================================================

run_phase_5() {
  header "Phase 5: CCM Removal"

  warn "⚠️  이 단계는 NLB를 재생성할 수 있습니다."
  warn "⚠️  유지보수 윈도우에서 실행하세요."

  confirm_proceed "CCM ArgoCD App 삭제?" && {
    cd "${PROJECT_ROOT}"

    # Archive CCM yaml
    mkdir -p archive/gitops-apps
    mv gitops-apps/bootstrap/aws-cloud-controller-manager.yaml \
       archive/gitops-apps/aws-cloud-controller-manager.yaml.bak 2>/dev/null || true

    git add -A
    git commit -m "feat: Phase 5 — Remove AWS Cloud Controller Manager

- CCM ArgoCD App archived
- ALBC fully manages NLB lifecycle
- NLB IP target mode = automatic Pod registration"
    git push
    ok "CCM removed"
  }

  checkpoint "Phase 5 Complete — Architecture Evolution Finished! 🎉"
}

# ==============================================================================
# Dispatcher
# ==============================================================================

case "$PHASE" in
  1) run_phase_1 ;;
  2) run_phase_2 ;;
  3) run_phase_3 ;;
  4) run_phase_4 ;;
  5) run_phase_5 ;;
  all)
    run_phase_1
    run_phase_2
    run_phase_3
    run_phase_4
    run_phase_5
    ;;
  *)
    err "Unknown phase: ${PHASE}"
    echo "Usage: $0 [1|2|3|4|5|all]"
    exit 1
    ;;
esac
