#!/bin/bash
set -e

ENV=$1
STACK=$2

if [ -z "$ENV" ] || [ -z "$STACK" ]; then
    echo "Usage: $0 <ENV> <STACK>"
    exit 1
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}================================================================================"
echo "Checking Status for Stack: $STACK (Env: $ENV) [상태 점검]"
echo -e "================================================================================${NC}"

# Retrieve Kubeconfig if RKE2 or Bootstrap
if [[ "$STACK" == "50-rke2" ]] || [[ "$STACK" == "55-bootstrap" ]]; then
    KUBECONFIG_PATH=~/.kube/config-rke2-$ENV
    if [ ! -f "$KUBECONFIG_PATH" ]; then
        echo -e "${RED}Error: Kubeconfig not found at $KUBECONFIG_PATH${NC}"
        echo -e "${YELLOW}오류: $KUBECONFIG_PATH 파일을 찾을 수 없습니다. 'make apply'를 먼저 실행해 주세요.${NC}"
        exit 1
    fi
    export KUBECONFIG=$KUBECONFIG_PATH

    # Ensure Tunnel is running (Idempotent call)
    ./scripts/common/tunnel.sh start-bg $ENV > /dev/null
fi

# Stack Specific Checks
if [[ "$STACK" == "55-bootstrap" ]]; then
    echo -e "\n${BOLD}>>> 1. ArgoCD GitOps Status (배포 현황)${NC}"
    APPS=$(kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status --no-headers 2>/dev/null || echo "")
    
    if [ -z "$APPS" ]; then
        echo -e "${YELLOW}Warning: No ArgoCD applications found. (애플리케이션이 아직 생성되지 않았습니다)${NC}"
    else
        echo -e "${BOLD}NAME                 SYNC STATUS     HEALTH STATUS   NOTES${NC}"
        while read -r name sync health; do
            case $sync in
                Synced)    sync_color=$GREEN;  sync_kr="(정상)" ;;
                OutOfSync) sync_color=$YELLOW; sync_kr="(동기화중)" ;;
                *)         sync_color=$RED;    sync_kr="(에러)" ;;
            esac
            case $health in
                Healthy)     health_color=$GREEN;  health_kr="(상태좋음)" ;;
                Progressing) health_color=$CYAN;   health_kr="(진행중)" ;;
                *)           health_color=$RED;    health_kr="(확인필요)" ;;
            esac
            printf "%-20s ${sync_color}%-15s${NC} ${health_color}%-15s${NC} %-15s\n" "$name" "$sync" "$health" "$health_kr"
        done <<< "$APPS"
    fi

    echo -e "\n${BOLD}>>> 2. System Pods Health (시스템 포드 상태)${NC}"
    FAILING_PODS=$(kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null || true)
    if [ -z "$FAILING_PODS" ]; then
        echo -e "${GREEN}✓ All core pods are Running or Completed. (모든 핵심 포드가 정상 작동 중입니다)${NC}"
    else
        echo -e "${RED}⚠ Found problematic pods (문제 발생 포드):${NC}"
        echo "$FAILING_PODS"
    fi

    # NEW: Stuck Namespace Detection
    echo -e "\n${BOLD}>>> 3. Namespace Health (네임스페이스 상태)${NC}"
    TERMINATING_NS=$(kubectl get ns | grep Terminating | awk '{print $1}' || echo "")
    if [ -z "$TERMINATING_NS" ]; then
        echo -e "${GREEN}✓ No namespaces stuck in termination. (정상)${NC}"
    else
        echo -e "${RED}⚠ Stuck Namespaces Detected! (삭제 중 멈춤):${NC}"
        for ns in $TERMINATING_NS; do
            echo -e "  - ${YELLOW}$ns${NC}"
        done
    fi

    # NEW: Stuck ArgoCD Applications Detection
    echo -e "\n${BOLD}>>> 4. ArgoCD Application Health (앱 리소스 상태)${NC}"
    STUCK_APPS=$(kubectl get applications -n argocd -o json | jq -r '.items[] | select(.metadata.deletionTimestamp != null) | .metadata.name' || echo "")
    if [ -z "$STUCK_APPS" ]; then
        echo -e "${GREEN}✓ No applications stuck in deletion. (정상)${NC}"
    else
        echo -e "${RED}⚠ Stuck Applications Detected! (삭제 중 멈춤):${NC}"
        for app in $STUCK_APPS; do
            echo -e "  - ${YELLOW}$app${NC}"
        done
    fi

    # NEW: Webhook Connectivity Check
    WEBHOOK_ERR_APPS=$(kubectl get applications -n argocd -o json | jq -r '.items[] | select(.status.conditions[]?.message | tostring | contains("failed calling webhook")) | .metadata.name' | sort -u || echo "")
    if [ -n "$WEBHOOK_ERR_APPS" ]; then
        echo -e "\n${RED}⚠ Webhook Deadlock Detected! (웹후크 연결 실패):${NC}"
        for app in $WEBHOOK_ERR_APPS; do
            echo -e "  - ${YELLOW}$app${NC}"
        done
    fi

    echo -e "\n${BOLD}>>> 5. External Traffic (Ingress - 외부 접속 주소)${NC}"
    INGRESSES=$(kubectl get ingress -A --no-headers 2>/dev/null || echo "")
    if [ -z "$INGRESSES" ]; then
        echo -e "${YELLOW}No Ingress resources found yet. (접속 주소가 아직 할당되지 않았습니다)${NC}"
    else
        kubectl get ingress -A
    fi
    
elif [[ "$STACK" == "60-database" ]]; then
    echo -e "\n${BOLD}>>> 1. Database Instance Status (From External Local - via SSM)${NC}"
    
    # Get Instance IDs from Terraform Output
    OUTPUT_JSON=$(terraform -chdir=stacks/$ENV/$STACK output -json 2>/dev/null || echo "{}")
    PG_INSTANCE_ID=$(echo "$OUTPUT_JSON" | jq -r '.postgres_instance_id.value // ""')
    NEO_INSTANCE_ID=$(echo "$OUTPUT_JSON" | jq -r '.neo4j_instance_id.value // ""')

    if [ -z "$PG_INSTANCE_ID" ] || [ "$PG_INSTANCE_ID" == "null" ]; then
        echo -e "${RED}Error: Could not retrieve Instance IDs. (Terraform output missing)${NC}"
    else
        check_instance_status() {
            local INSTANCE_ID=$1
            local NAME=$2
            echo -e "${YELLOW}Checking $NAME ($INSTANCE_ID)...${NC}"
            
            # Check SSM Connection
            SSM_STATUS=$(aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$INSTANCE_ID" --query "InstanceInformationList[0].PingStatus" --output text 2>/dev/null || echo "Unknown")
            
            if [ "$SSM_STATUS" == "Online" ]; then
                 echo -e "${GREEN}✓ SSM Agent Online${NC}"
                 # Run Docker PS
                 echo -e "  > Executing 'docker ps' via SSM..."
                 CMD_ID=$(aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["docker ps --format \"table {{.Names}}\\t{{.Status}}\\t{{.Ports}}\""]' --query "Command.CommandId" --output text)
                 
                 # Wait for result
                 for i in {1..10}; do
                    STATUS=$(aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" --query "Status" --output text 2>/dev/null || echo "Pending")
                    if [[ "$STATUS" == "Success" || "$STATUS" == "Failed" ]]; then
                        break
                    fi
                    echo -n "."
                    sleep 1
                 done
                 echo ""
                 
                 aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" --query "StandardOutputContent" --output text
            else
                 echo -e "${RED}⚠ SSM Agent Offline. Status: $SSM_STATUS${NC}"
                 echo -e "  (인스턴스가 부팅 중이거나, Outbound 인터넷/VPC Endpoint가 없어 SSM 연결이 실패했을 수 있습니다)"
            fi
        }

        check_instance_status "$PG_INSTANCE_ID" "PostgreSQL"
        echo "---------------------------------------------------"
        check_instance_status "$NEO_INSTANCE_ID" "Neo4j"
    fi

else
    # Default: Show Terraform Outputs
    echo -e "\n${BOLD}>>> Terraform Outputs for $STACK (기본 출력 정보)${NC}"
    terraform -chdir=stacks/$ENV/$STACK output 2>/dev/null || echo "No outputs found or Terraform not initialized."
fi

echo -e "\n${CYAN}================================================================================${NC}"
