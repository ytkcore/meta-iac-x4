#!/bin/bash
set -euo pipefail

# 설정
ENV="dev"
PROJECT="meta"
# CP 노드 중 하나를 선택 (Tag: Name=*cp-01*)
CP_INSTANCE_NAME="${ENV}-${PROJECT}-k8s-cp-01"

# Control Plane IP 및 Instance ID 조회
echo "Fetching Control Plane Info ($CP_INSTANCE_NAME)..."
read CP_ID CP_IP <<< $(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${CP_INSTANCE_NAME}" "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].[InstanceId, PrivateIpAddress]" --output text)

if [ "$CP_ID" == "None" ] || [ -z "$CP_ID" ]; then
    echo "Error: Control Plane ($CP_INSTANCE_NAME) not found or not running."
    exit 1
fi
echo "Control Plane ID: $CP_ID"
echo "Control Plane IP: $CP_IP"

# Kubeconfig 가져오기 (Direct SSM)
TARGET_KUBECONFIG="${HOME}/.kube/config-rke2-${ENV}"
echo "Downloading kubeconfig from Control Plane via AWS SSM..."

# AWS SSM을 통해 Command 실행 후 Output 캡처
# 주의: ssm start-session은 interactive용이므로 ssm send-command 사용 권장하나,
# 간편하게 AWS-RunShellScript로 cat 실행
COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$CP_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["sudo cat /etc/rancher/rke2/rke2.yaml"]' \
    --query "Command.CommandId" --output text)

echo "Waiting for SSM command ($COMMAND_ID) execution..."
sleep 2

# Output 조회
aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$CP_ID" \
    --query "StandardOutputContent" --output text > "$TARGET_KUBECONFIG"

if [ ! -s "$TARGET_KUBECONFIG" ]; then
    echo "Error: Kubeconfig is empty. Check SSM logs."
    aws ssm get-command-invocation --command-id "$COMMAND_ID" --instance-id "$CP_ID"
    exit 1
fi

# 로컬 접근용 수정 (127.0.0.1)
sed -i '' 's/127.0.0.1/127.0.0.1/g' "$TARGET_KUBECONFIG" # No-op but checks file
# 인증서 무시 옵션 권장 (로컬 터널링 시 도메인 불일치)

echo "Kubeconfig saved to: $TARGET_KUBECONFIG"
echo ""
echo "To access the cluster WITHOUT Bastion:"
echo "1. Start SSM Port Forwarding directly to CP Node:"
echo "   aws ssm start-session --target $CP_ID \\"
echo "     --document-name AWS-StartPortForwardingSessionToRemoteHost \\"
echo "     --parameters '{\"portNumber\":[\"6443\"],\"localPortNumber\":[\"6443\"]}'"
echo ""
echo "2. Export Kubeconfig:"
echo "   export KUBECONFIG=$TARGET_KUBECONFIG"
echo ""
echo "3. Test:"
echo "   kubectl get nodes"
