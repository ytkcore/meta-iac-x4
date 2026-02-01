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
    
    # Interpretation & Advice
    echo -e "\n${BOLD}>>> 💡 Interpretation & Required Actions (상태 해석 및 필수 조치)${NC}"
    
    # 1. Action for Stuck Namespaces
    if [ -n "$TERMINATING_NS" ]; then
        echo -e "${RED}[필수 조치] 네임스페이스 삭제 고착 해결 (Stuck Namespace)${NC}"
        echo -e "  다음 명령어를 실행하여 멈춘 네임스페이스를 강제 정리하세요:"
        for ns in $TERMINATING_NS; do
            echo -e "  ${CYAN}kubectl get ns $ns -o json | jq '.spec.finalizers = []' | kubectl replace --raw \"/api/v1/namespaces/$ns/finalize\" -f -${NC}"
        done
    fi

    # 2. Action for Stuck Apps
    if [ -n "$STUCK_APPS" ]; then
        echo -e "${RED}[필수 조치] ArgoCD 애플리케이션 삭제 고착 해결 (Stuck Application)${NC}"
        echo -e "  다음 명령어를 실행하여 멈춘 앱의 Finalizer를 강제 제거하세요:"
        for app in $STUCK_APPS; do
            echo -e "  ${CYAN}kubectl patch application $app -n argocd --type merge -p '{\"metadata\":{\"finalizers\":[]}}'${NC}"
        done
    fi

    # 2.1 Action for Webhook Deadlock
    if [ -n "$WEBHOOK_ERR_APPS" ]; then
        echo -e "${RED}[필수 조치] 유령 웹후크로 인한 삭제 고착 (Webhook Deadlock)${NC}"
        echo -e "  삭제된 컨트롤러(Ingress 등)의 ValidatingWebhookConfiguration이 남아있어 삭제가 차단되었습니다."
        echo -e "  다음 명령어로 범인을 찾아 삭제하세요:"
        echo -e "  ${CYAN}kubectl get validatingwebhookconfigurations${NC}"
        echo -e "  ${CYAN}kubectl delete validatingwebhookconfiguration <의심되는-이름>${NC} (예: rke2-ingress-nginx-admission)"
    fi

    # 3. Action for Unknown Status
    if echo "$APPS" | grep -q "Unknown"; then
        echo -e "${YELLOW}[권장 조치] 'Unknown' 상태 감지 (Sync Status Unknown)${NC}"
        echo -e "  ArgoCD 내부 통신 장애(repo-server 재시작 등)가 의심됩니다."
        echo -e "  - 1~2분 정도 대기하면 자동으로 해결됩니다."
        echo -e "  - 만약 지속된다면 'argocd-repo-server'의 메모리 부족(OOM)을 의심해보세요."
        echo -e "  - 즉시 해결을 원하시면 해당 앱을 'Refresh' 하세요."
    fi

    # 4. Action for Image Pull Errors
    IMAGE_PULL_ERRS=$(kubectl get pods -A -o json | jq -r '.items[] | select(.status.containerStatuses[].state.waiting.reason | . == "ImagePullBackOff" or . == "ErrImagePull") | "\(.metadata.namespace)/\(.metadata.name)"' | sort -u || echo "")
    if [ -n "$IMAGE_PULL_ERRS" ]; then
        echo -e "${RED}[필수 조치] 이미지 풀링 에러 감지 (Image Pull Error)${NC}"
        echo -e "  다음 포드들이 이미지를 가져오지 못하고 있습니다:"
        for pod in $IMAGE_PULL_ERRS; do
            echo -e "  - ${YELLOW}$pod${NC}"
        done
        echo -e "  - 해결책: 이미지 태그가 정확한지, registry(docker.io, public.ecr.aws 등) 주소가 맞는지 확인하세요."
        echo -e "  - 프라이빗 레지스트리인 경우 ImagePullSecret이 설정되었는지 확인하세요."
    fi

    # 5. Action for OOMKilled Pods
    OOM_PODS=$(kubectl get pods -A -o json | jq -r '.items[] | select(.status.containerStatuses[].lastState.terminated.reason == "OOMKilled") | "\(.metadata.namespace)/\(.metadata.name)"' | sort -u || echo "")
    if [ -n "$OOM_PODS" ]; then
        echo -e "${RED}[필수 조치] 메모리 부족 종료 감지 (OOMKilled)${NC}"
        echo -e "  다음 포드들이 메모리 부족으로 인해 재시작되었습니다:"
        for pod in $OOM_PODS; do
            echo -e "  - ${YELLOW}$pod${NC}"
        done
        echo -e "  - 해결책: Terraform 또는 Helm Values에서 해당 컴포넌트의 'memory limit'을 늘려주세요."
        echo -e "  - 예: argo-cd의 경우 'repo_server.limits.memory' 값을 1Gi 등으로 상향 조정."
    fi

    # 4. Action for Apps Sync
    if [ -z "$TERMINATING_NS" ] && [ -z "$STUCK_APPS" ]; then
        if echo "$APPS" | grep -q "OutOfSync"; then
            echo -e "- ${CYAN}정보: ArgoCD가 동기화 중입니다. (일반적으로 2~3분 소요)${NC}"
        fi

        if echo "$APPS" | grep -q "Missing"; then
             echo -e "- ${YELLOW}정보: 앱 리소스가 생성 대기 중입니다. 비정상 포드가 없다면 잠시만 기다려 주세요.${NC}"
        fi

        if ! echo "$APPS" | grep -qE "OutOfSync|Missing|Unknown"; then
            echo -e "- ${GREEN}상태: 모든 시스템이 안정적입니다. 정상 이용 가능합니다.${NC}"
        fi
    fi

else
    # Default: Show Terraform Outputs
    echo -e "\n${BOLD}>>> Terraform Outputs for $STACK (기본 출력 정보)${NC}"
    terraform -chdir=stacks/$ENV/$STACK output 2>/dev/null || echo "No outputs found or Terraform not initialized."
fi

echo -e "\n${CYAN}================================================================================${NC}"
