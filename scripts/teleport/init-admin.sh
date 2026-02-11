#!/bin/bash
set -euo pipefail

# 환경변수에서 파라미터 읽기 (기본값 포함)
USERNAME="${TELEPORT_USERNAME:-platform-admin}"
ROLES="${TELEPORT_ROLES:-editor,access}"
LOGINS="${TELEPORT_LOGINS:-root,ubuntu,ec2-user}"

# Find Teleport Pod
POD=$(kubectl get pods -n teleport -l app.kubernetes.io/name=teleport -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$POD" ]; then
    echo "오류: Teleport 파드를 찾을 수 없습니다."
    exit 1
fi

# Create User and Capture Output
OUTPUT=$(kubectl exec -n teleport "$POD" -- tctl users add "$USERNAME" --roles="$ROLES" --logins="$LOGINS" 2>&1)

if [[ $? -ne 0 ]]; then
    echo "오류: 사용자 생성 실패:"
    echo "$OUTPUT"
    exit 1
fi

# Extract URL
URL=$(echo "$OUTPUT" | grep -o 'https://teleport.unifiedmeta.net/web/invite/[a-zA-Z0-9]*')

if [ -z "$URL" ]; then
    echo "사용자가 생성되었으나 초대 링크 파싱에 실패했습니다."
    echo "$OUTPUT"
else
    echo "관리자 계정 생성 완료! 초대 링크:"
    echo "$URL"
fi
