#!/bin/bash
set -euo pipefail

# 설정
ENV="dev"
PROJECT="meta"
# Load common logging utility
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export LOG_FILE="${ROOT_DIR}/logs/ssm/get-kubeconfig-$(date +%Y%m%d).log"
source "${ROOT_DIR}/scripts/common/logging.sh"

# CP 노드 태그 패턴 (dev-meta-k8s-cp-*)
CP_NAME_PATTERN="${ENV}-${PROJECT}-k8s-cp-*"

# Control Plane 목록 조회 (InstanceId, PrivateIp)
header "Fetching Control Plane Nodes ($CP_NAME_PATTERN)..."
# Read result into an array
# Using process substitution to avoid subshell variable loss
declare -a CP_IDS
declare -a CP_IPS
while read -r ID IP; do
    CP_IDS+=("$ID")
    CP_IPS+=("$IP")
done < <(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${CP_NAME_PATTERN}" "Name=instance-state-name,Values=running" \
    --query "Reservations[].Instances[].[InstanceId, PrivateIpAddress]" --output text)

COUNT=${#CP_IDS[@]}
if [ "$COUNT" -eq 0 ]; then
    echo "Error: No running Control Plane nodes found."
    exit 1
fi

echo "Found $COUNT Control Plane nodes: ${CP_IDS[*]}"
TARGET_KUBECONFIG="${HOME}/.kube/config-rke2-${ENV}"
SUCCESS=false
FINAL_CP_IP=""

# 노드 순회하며 시도
for ((idx=0; idx<COUNT; idx++)); do
    CP_ID="${CP_IDS[$idx]}"
    CP_IP="${CP_IPS[$idx]}"
    
    echo "--------------------------------------------------"
    echo "Attempting to retrieve kubeconfig from $CP_ID ($CP_IP)..."
    
    # SSM Command 실행 (타임아웃은 개별 60초로 단축, 전체 300초가 아니므로)
    # 여러 노드를 돌아야 하므로 노드당 대기 시간은 줄임 (예: 60초)
    # 하지만 파일 생성 자체를 기다려야 한다면 길게 잡아야 함.
    # 전략: 첫 번째 노드가 실패하면 다음 노드로 감.
    # 단, '파일이 없다'는 이유로 실패하는 건지 'SSM이 안 되는' 건지 구분 필요.
    # 여기서는 'SSM 연결 불가' 또는 '타임아웃' 시 다음 노드로 이동.
    
    COMMAND_ID=$(aws ssm send-command \
        --instance-ids "$CP_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["sudo bash -c \"timeout 60 bash -c \\\"until [ -f /etc/rancher/rke2/rke2.yaml ]; do sleep 2; done; cat /etc/rancher/rke2/rke2.yaml\\\"\""]' \
        --query "Command.CommandId" --output text 2>/dev/null || echo "FAIL")
    
    if [ "$COMMAND_ID" == "FAIL" ] || [ -z "$COMMAND_ID" ]; then
        echo "  -> Failed to send SSM command. Skipping node."
        continue
    fi
    
    echo "  -> Command ID: $COMMAND_ID. Waiting for result..."
    
    # Local Wait Loop
    NODE_SUCCESS=false
    MAX_RETRIES=40 # 2s * 40 = 80s (Matches remote timeout 60s + buffer)
    SLEEP_SEC=2
    
    for ((i=1; i<=MAX_RETRIES; i++)); do
        STATUS=$(aws ssm list-command-invocations \
            --command-id "$COMMAND_ID" \
            --instance-id "$CP_ID" \
            --query "CommandInvocations[0].Status" --output text 2>/dev/null || echo "Unknown")
        
        if [ "$STATUS" == "Success" ]; then
            NODE_SUCCESS=true
            break
        elif [ "$STATUS" == "Failed" ] || [ "$STATUS" == "Cancelled" ] || [ "$STATUS" == "TimedOut" ]; then
             echo "  -> SSM Status: $STATUS. Aborting this node."
             break
        fi
        
        if [ $((i % 5)) -eq 0 ]; then
             echo -n "."
        fi
        sleep $SLEEP_SEC
    done
    echo ""
    
    if [ "$NODE_SUCCESS" == "true" ]; then
        # Output 조회
        aws ssm get-command-invocation \
            --command-id "$COMMAND_ID" \
            --instance-id "$CP_ID" \
            --query "StandardOutputContent" --output text > "$TARGET_KUBECONFIG"
            
        # Validation
        if [ -s "$TARGET_KUBECONFIG" ] && [ "$(cat "$TARGET_KUBECONFIG" | wc -c)" -gt 5 ] && grep -q "apiVersion" "$TARGET_KUBECONFIG"; then
            echo "  -> Success! Valid kubeconfig retrieved."
            SUCCESS=true
            FINAL_CP_IP="$CP_IP"
            break
        else
            echo "  -> Invalid content received. Skipping node."
        fi
    else
        echo "  -> Timeout or Failure waiting for node $CP_ID."
    fi
done

if [ "$SUCCESS" == "false" ]; then
    echo "Error: Failed to retrieve kubeconfig from ALL $COUNT Control Plane nodes."
    exit 1
fi

# 로컬 접근용 수정 (127.0.0.1)
sed -i '' 's/127.0.0.1/127.0.0.1/g' "$TARGET_KUBECONFIG"

echo ""
echo "Kubeconfig saved to: $TARGET_KUBECONFIG"
echo ""

# Update env.tfvars
TFVARS_FILE="stacks/${ENV}/env.tfvars"
if [ -f "$TFVARS_FILE" ]; then
    echo "Updating $TFVARS_FILE..."
    if grep -Fq "kubeconfig_path = \"${TARGET_KUBECONFIG}\"" "$TFVARS_FILE"; then
         :
    elif grep -q "kubeconfig_path" "$TFVARS_FILE"; then
        sed "s|kubeconfig_path.*|kubeconfig_path = \"${TARGET_KUBECONFIG}\"|g" "$TFVARS_FILE" > "${TFVARS_FILE}.tmp" && mv "${TFVARS_FILE}.tmp" "$TFVARS_FILE"
    else
        echo "" >> "$TFVARS_FILE"
        echo "kubeconfig_path = \"${TARGET_KUBECONFIG}\"" >> "$TFVARS_FILE"
    fi
fi

echo "Detailed Access Info for $FINAL_CP_IP:"
echo "   aws ssm start-session --target $CP_ID --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters '{\"portNumber\":[\"6443\"],\"localPortNumber\":[\"6443\"]}'"
echo "   export KUBECONFIG=$TARGET_KUBECONFIG"

