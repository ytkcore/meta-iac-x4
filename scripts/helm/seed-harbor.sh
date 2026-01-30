#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Harbor OCI Seeding Script
# 
# Purpose:
#   Download Helm charts from external repositories and push them to Harbor OCI.
#   This ensures the cluster can pull charts even in air-gapped scenarios (if pre-seeded)
#   or simply caches them for faster/reliable access.
#
# Environment Variables Check:
#   HARBOR_HOST, ADMIN_PASS, PROJECT must be set.
# -----------------------------------------------------------------------------

log() { echo "[seed] $*"; }
error() { echo "[seed] ERROR: $*" >&2; exit 1; }

# Validate inputs
if [[ -z "${HARBOR_HOST:-}" ]]; then error "HARBOR_HOST is required"; fi
if [[ -z "${ADMIN_PASS:-}" ]]; then error "ADMIN_PASS is required"; fi
if [[ -z "${PROJECT:-}" ]]; then PROJECT="helm-charts"; fi
if [[ "${ENABLE_SEED:-true}" != "true" ]]; then
    log "Auto seeding disabled (ENABLE_SEED!=true). Skipping."
    exit 0
fi

# Configuration
HARBOR_URL="https://${HARBOR_HOST}"
TEMP_DIR="/tmp/harbor-oci-seed-${PROJECT}"

# 1. Wait for Harbor Readiness
log "Waiting for Harbor registry endpoint: ${HARBOR_URL}/v2/"
for i in $(seq 1 60); do
    code="$(curl -ks -o /dev/null -w '%{http_code}' "${HARBOR_URL}/v2/" || true)"
    if [[ "$code" == "200" || "$code" == "401" || "$code" == "403" ]]; then
        log "Harbor /v2 ready (HTTP $code)"
        break
    fi
    sleep 2
done

# 2. Ensure Project Exists (Best Effort)
log "Ensuring Harbor project '${PROJECT}' exists..."
curl -fsS -u "admin:${ADMIN_PASS}" -X POST "${HARBOR_URL}/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -d '{"project_name":"'"$PROJECT"'","public":true}' >/dev/null 2>&1 || true

# 3. Helm Registry Login
log "Logging in to Helm registry: ${HARBOR_HOST}"
echo "${ADMIN_PASS}" | helm registry login "${HARBOR_HOST}" -u admin --password-stdin >/dev/null

# 4. Chart Seeding Function
ensure_chart() {
    local alias="$1"
    local repo_url="$2"
    local chart_name="$3"
    local chart_version="$4"
    
    local oci_url="oci://${HARBOR_HOST}/${PROJECT}"
    
    # Check if chart exists in Harbor
    if helm show chart "${oci_url}/${chart_name}" --version "${chart_version}" >/dev/null 2>&1; then
        log "OK: ${chart_name}:${chart_version} already exists in Harbor OCI"
        return 0
    fi

    log "Missing: ${chart_name}:${chart_version} -> Pulling from ${repo_url}"
    
    # Prepare temp dir
    rm -rf "${TEMP_DIR}" && mkdir -p "${TEMP_DIR}"
    
    # Add repo & pull
    helm repo add "${alias}" "${repo_url}" --force-update >/dev/null
    helm repo update "${alias}" >/dev/null
    
    if ! helm pull "${alias}/${chart_name}" --version "${chart_version}" -d "${TEMP_DIR}"; then
        log "WARNING: Failed to pull ${chart_name}:${chart_version} from ${alias}. Skipping."
        return 1
    fi
    
    # Push to Harbor
    local package_name
    package_name=$(ls "${TEMP_DIR}"/*.tgz | head -n 1)
    
    if [[ -f "$package_name" ]]; then
        log "Pushing $(basename "$package_name") to ${oci_url}..."
        if helm push "$package_name" "${oci_url}" >/dev/null; then
            log "SUCCESS: Pushed ${chart_name}:${chart_version}"
        else
            log "ERROR: Failed to push ${chart_name}:${chart_version}"
            return 1
        fi
    else
        log "ERROR: Package file not found for ${chart_name}:${chart_version}"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Seed Charts
# -----------------------------------------------------------------------------

# Cleanup temp on exit
trap 'rm -rf ${TEMP_DIR}' EXIT

# ArgoCD (required)
if [[ -n "${ARGOCD_VERSION:-}" ]]; then
    ensure_chart "argo" "https://argoproj.github.io/argo-helm" "argo-cd" "${ARGOCD_VERSION}"
else
    log "ARGOCD_VERSION not set. Skipping ArgoCD seeding."
fi

# Cert Manager (optional)
if [[ -n "${CERT_MANAGER_VERSION:-}" ]]; then
    ensure_chart "jetstack" "https://charts.jetstack.io" "cert-manager" "${CERT_MANAGER_VERSION}"
else
    log "CERT_MANAGER_VERSION not set. Skipping Cert-Manager seeding."
fi

# Rancher (optional)
if [[ -n "${RANCHER_VERSION:-}" ]]; then
    ensure_chart "rancher" "https://releases.rancher.com/server-charts/stable" "rancher" "${RANCHER_VERSION}"
else
    log "RANCHER_VERSION not set. Skipping Rancher seeding."
fi

# Cleanup repos
helm repo remove argo jetstack rancher >/dev/null 2>&1 || true
log "Seeding complete."
