#!/bin/bash
set -euo pipefail

echo "ArgoCD 동기화 시작..."

# Get all application names
APPS=$(kubectl get applications -n argocd -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

if [ -z "$APPS" ]; then
    echo "ArgoCD 애플리케이션을 찾을 수 없습니다."
    exit 0
fi

echo "발견된 애플리케이션: $APPS"

# Sync each app
for APP in $APPS; do
    echo "$APP 동기화 중..."
    # Patch the application to trigger a sync
    kubectl patch application "$APP" -n argocd --type merge -p '{"operation": {"sync": {"prune": true}}}' || echo "$APP 동기화 실패"
done

echo "모든 애플리케이션에 대한 동기화 요청이 전송되었습니다."
