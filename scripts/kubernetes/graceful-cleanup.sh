#!/bin/bash
# =============================================================================
# Kubernetes Graceful Cleanup Script
# Usage: ./graceful-cleanup.sh <kubeconfig_path>
# =============================================================================

set -uo pipefail

KUBECONFIG_PATH="${1:-}"

if [[ -z "${KUBECONFIG_PATH}" ]]; then
  echo "Error: Kubeconfig path is required."
  exit 1
fi

export KUBECONFIG="${KUBECONFIG_PATH}"

echo "Starting graceful cleanup of Kubernetes resources..."

# 1. Delete ArgoCD Root App and wait
if kubectl get application root-apps -n argocd &>/dev/null; then
  echo "Deleting ArgoCD Root App (this may take a few minutes)..."
  # Add finalizer if missing to ensure cascading delete
  kubectl patch application root-apps -n argocd -p '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}' --type merge &>/dev/null
  kubectl delete application root-apps -n argocd --wait=true --timeout=120s || {
    echo "Warning: Timeout waiting for root-apps deletion. Removing finalizer to proceed..."
    kubectl patch application root-apps -n argocd -p '{"metadata":{"finalizers":null}}' --type merge &>/dev/null
    kubectl delete application root-apps -n argocd --wait=false &>/dev/null
  }
fi

# 2. Remove blocking webhooks (CRITICAL for clean destroy)
# These webhooks often block deletion of secrets, namespaces, and other resources
# if the webhook server (Rancher/Cert-Manager) is already partially down.
echo "Removing potentially blocking webhooks..."
WEBHOOKS=(
  "rancher.cattle.io"
  "validating-webhook-configuration"
  "mutating-webhook-configuration"
  "cert-manager-webhook"
)

for hook in "${WEBHOOKS[@]}"; do
  kubectl delete validatingwebhookconfigurations "${hook}" --ignore-not-found --wait=false &>/dev/null
  kubectl delete mutatingwebhookconfigurations "${hook}" --ignore-not-found --wait=false &>/dev/null
done

# Force remove any rancher-labeled webhooks
kubectl delete validatingwebhookconfigurations -l "app.kubernetes.io/part-of=rancher" --ignore-not-found &>/dev/null
kubectl delete mutatingwebhookconfigurations -l "app.kubernetes.io/part-of=rancher" --ignore-not-found &>/dev/null

# 3. Force delete all Services of type LoadBalancer
echo "Cleaning up all LoadBalancer services..."
LBS=$(kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}' 2>/dev/null)
if [[ -n "${LBS}" ]]; then
  for lb in ${LBS}; do
    echo "  -> Deleting Service: ${lb}"
    kubectl delete svc -n ${lb%/*} ${lb#*/} --wait=false &>/dev/null
  done
  # Wait briefly for cloud provider to initiate LB cleanup
  sleep 5
fi

echo "Graceful cleanup complete."
