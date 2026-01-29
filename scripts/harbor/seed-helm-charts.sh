#!/bin/bash
# Harbor Helm Chart Seeding Script
# Installed to: /opt/harbor/seed-helm-charts.sh
set -euo pipefail

LOG_FILE="/var/log/harbor-helm-seed.log"
exec >> "$LOG_FILE" 2>&1
echo "=== Helm Chart Seeding Started: $(date) ==="

export HOME=/root
export HELM_EXPERIMENTAL_OCI=1

API_HOST="127.0.0.1"
API_URL="http://$API_HOST/api/v2.0"
AUTH="admin:$HARBOR_ADMIN_PASSWORD"
OCI_REGISTRY_HOST="$API_HOST"
OCI_URL="oci://$OCI_REGISTRY_HOST/helm-charts"

retry() {
  local max="$1" delay="$2" attempt=1
  shift 2
  until "$@"; do
    if ((attempt >= max)); then
      echo "[ERROR] Command failed after $max attempts: $*"
      return 1
    fi
    echo "[WARN] Attempt $attempt failed, retrying in ${delay}s..."
    ((attempt++))
    sleep "$delay"
  done
  echo "[OK] Command succeeded: $*"
}

wait_harbor_healthy() {
  echo "[INFO] Waiting for Harbor to be healthy..."
  for i in {1..60}; do
    if curl -fsSk "$API_URL/health" 2>/dev/null | grep -q '"status":"healthy"'; then
      echo "[OK] Harbor is healthy"
      return 0
    fi
    echo "[INFO] Harbor not ready yet (attempt $i/60)..."
    sleep 10
  done
  echo "[ERROR] Harbor health check timed out"
  return 1
}

install_helm() {
  if command -v helm &>/dev/null; then
    echo "[OK] Helm already installed: $(helm version --short)"
    return 0
  fi
  echo "[INFO] Installing Helm..."
  
  local script="/tmp/get-helm-3.sh"
  local attempt=0
  local max_attempts=3
  
  while ((attempt < max_attempts)); do
    if curl -fsSL -o "$script" https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 2>&1; then
      chmod +x "$script"
      break
    fi
    ((attempt++))
    echo "[WARN] Download attempt $attempt failed, retrying in 10s..."
    sleep 10
  done
  
  if [[ ! -f "$script" ]]; then
    echo "[ERROR] Failed to download Helm install script"
    return 1
  fi
  
  if bash "$script" 2>&1; then
    rm -f "$script"
    echo "[OK] Helm installed successfully"
    return 0
  else
    rm -f "$script"
    echo "[ERROR] Helm installation failed"
    return 1
  fi
}

create_helm_project() {
  echo "[INFO] Creating helm-charts project..."
  local resp
  resp=$(curl -fsSk -u "$AUTH" -w "%{http_code}" -o /dev/null \
    -X POST "$API_URL/projects" \
    -H "Content-Type: application/json" \
    -d '{"project_name":"helm-charts","public":true}' 2>/dev/null) || true
  
  if [[ "$resp" == "201" ]]; then
    echo "[OK] helm-charts project created"
  elif [[ "$resp" == "409" ]]; then
    echo "[OK] helm-charts project already exists"
  else
    echo "[WARN] Project creation returned: $resp (may already exist)"
  fi
}

login_registry() {
  echo "[INFO] Logging into Harbor OCI registry at $OCI_REGISTRY_HOST..."
  if echo "$HARBOR_ADMIN_PASSWORD" | helm registry login "$OCI_REGISTRY_HOST" -u admin --password-stdin --plain-http 2>&1; then
    echo "[OK] Helm registry login successful"
    return 0
  else
    echo "[ERROR] Helm registry login failed"
    return 1
  fi
}

seed_chart() {
  local repo_name="$1" repo_url="$2" chart_name="$3" chart_version="$4"
  
  echo "[INFO] Seeding chart: $chart_name (version: $chart_version)"
  cd /tmp
  rm -f ${chart_name}*.tgz 2>/dev/null || true
  
  if ! helm repo add "$repo_name" "$repo_url" --force-update 2>&1; then
    echo "[ERROR] Failed to add repo: $repo_name"
    return 1
  fi
  helm repo update "$repo_name" 2>&1 || true
  
  if ! helm pull "$repo_name/$chart_name" --version "$chart_version" 2>&1; then
    echo "[ERROR] Failed to pull chart: $repo_name/$chart_name:$chart_version"
    return 1
  fi
  
  local tgz_file=$(ls ${chart_name}*.tgz 2>/dev/null | head -1)
  if [[ -z "$tgz_file" ]]; then
    echo "[ERROR] Chart file not found after pull"
    return 1
  fi
  
  if helm push "$tgz_file" "$OCI_URL" --plain-http 2>&1; then
    echo "[OK] Successfully pushed: $chart_name:$chart_version"
  else
    echo "[ERROR] Failed to push chart: $chart_name"
    rm -f "$tgz_file" 2>/dev/null || true
    return 1
  fi
  
  rm -f "$tgz_file" 2>/dev/null || true
  return 0
}

main() {
  wait_harbor_healthy || exit 1
  install_helm || exit 1
  create_helm_project
  
  retry 5 10 login_registry || {
    echo "[ERROR] Cannot login to registry, aborting seeding"
    exit 1
  }
  
  local failed=0
  
  seed_chart "argo" "https://argoproj.github.io/argo-helm" "argo-cd" "$HARBOR_ARGOCD_VER" || ((failed++))
  seed_chart "jetstack" "https://charts.jetstack.io" "cert-manager" "$HARBOR_CERTMANAGER_VER" || ((failed++))
  seed_chart "rancher" "https://releases.rancher.com/server-charts/stable" "rancher" "$HARBOR_RANCHER_VER" || ((failed++))
  
  helm repo remove argo jetstack rancher 2>/dev/null || true
  
  if ((failed > 0)); then
    echo "[WARN] Helm seeding completed with $failed failures"
    exit 1
  fi
  
  echo "=== Helm Chart Seeding Completed Successfully: $(date) ==="
}

main "$@"
