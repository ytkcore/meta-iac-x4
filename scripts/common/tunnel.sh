#!/usr/bin/env bash

# =================================================================================
# SSM Tunnel Manager (Auto-Integration)
# =================================================================================
# Description:
#   Manages SSM Session for Kubernetes access.
#   Supports checking status, starting in background, and stopping.
# Usage:
#   ./scripts/common/tunnel.sh [mode] [ENV]
# Modes:
#   check    : Returns 0 if tunnel is active (port 6443 open), 1 otherwise
#   start-bg : Starts tunnel in background if not active
#   stop     : Stops the background tunnel
# =================================================================================

set -e

MODE="${1:-check}"
ENV="${2:-dev}"
STACK="50-rke2"
STACK_DIR="stacks/${ENV}/${STACK}"
PID_FILE=".tunnel.pid"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Utility: Check if port 6443 is valid
check_port() {
    if lsof -i :6443 -sTCP:LISTEN -t >/dev/null ; then
        return 0
    else
        return 1
    fi
}

start_tunnel() {
    # Check dependencies
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}Error: 'aws' CLI is not installed.${NC}"
        exit 1
    fi

    # Retrieve Instance ID
    echo -e "${YELLOW}[SSM Tunnel] Retrieving Control Plane Instance ID...${NC}"
    pushd "${STACK_DIR}" > /dev/null
    if [ ! -d ".terraform" ]; then
         terraform init -reconfigure > /dev/null
    fi
    # Use -raw for plain string output if possible, but output is list
    INSTANCE_IDS_JSON=$(terraform output -json control_plane_instance_ids 2>/dev/null || echo "[]")
    popd > /dev/null
    
    INSTANCE_ID=$(echo "${INSTANCE_IDS_JSON}" | grep -o 'i-[a-zA-Z0-9]*' | head -n 1)

    # Fallback: If Terraform output is empty (e.g. state not fully populated/applied yet), try AWS CLI
    if [ -z "${INSTANCE_ID}" ]; then
        echo -e "${YELLOW}[SSM Tunnel] Terraform output empty. Falling back to AWS CLI search...${NC}"
        # Assume standard naming convention: {ENV}-meta-k8s-cp-*
        # We need to know PROJECT. Default to 'meta'.
        # Or parse from env.tfvars?
        PROJECT="meta"
        if [ -f "stacks/${ENV}/env.tfvars" ]; then
             PROJECT=$(grep 'project' "stacks/${ENV}/env.tfvars" | cut -d'"' -f2 | tr -d ' ' || echo "meta")
        fi
        
        # Search for any cp instance
        # Pattern: ${ENV}-${PROJECT}-k8s-cp-*
        INSTANCE_ID=$(aws ec2 describe-instances \
            --filters "Name=tag:Name,Values=${ENV}-${PROJECT}-k8s-cp-*" "Name=instance-state-name,Values=running" \
            --query "Reservations[].Instances[].InstanceId" \
            --output text | awk '{print $1}')
    fi

    if [ -z "${INSTANCE_ID}" ]; then
        echo -e "${RED}Error: Could not find Control Plane instance ID in ${STACK} (Terraform output & AWS CLI both failed).${NC}"
        # Do not exit with error to avoid blocking CI pipes where tunnel might be handled externally
        # But for local dev, this is critical.
        return 1
    fi

    echo -e "${GREEN}[SSM Tunnel] Starting background tunnel to ${INSTANCE_ID}...${NC}"
    
    # Start in background
    nohup aws ssm start-session \
        --target "${INSTANCE_ID}" \
        --document-name AWS-StartPortForwardingSession \
        --parameters '{"portNumber":["6443"],"localPortNumber":["6443"]}' \
        > /dev/null 2>&1 &
    
    PID=$!
    echo $PID > "${PID_FILE}"
    
    # Wait for port to open
    echo -n "Waiting for tunnel..."
    for i in {1..10}; do
        if check_port; then
            echo -e " ${GREEN}Connected!${NC}"
            return 0
        fi
        sleep 1
        echo -n "."
    done
    
    echo -e " ${RED}Timeout!${NC}"
    kill $PID
    rm "${PID_FILE}"
    return 1
}

stop_tunnel() {
    if [ -f "${PID_FILE}" ]; then
        PID=$(cat "${PID_FILE}")
        if ps -p $PID > /dev/null; then
             echo -e "${YELLOW}[SSM Tunnel] Stopping tunnel (PID: $PID)...${NC}"
             kill $PID
        fi
        rm "${PID_FILE}"
    else
        # Try finding by port using lsof just in case PID file is missing
        PID=$(lsof -i :6443 -sTCP:LISTEN -t)
        if [ ! -z "$PID" ]; then
             echo -e "${YELLOW}[SSM Tunnel] Stopping tunnel found on port 6443 (PID: $PID)...${NC}"
             kill $PID
        else
             echo "No active tunnel found."
        fi
    fi
}

# Main Logic
case "${MODE}" in
    check)
        if check_port; then
            exit 0
        else
            exit 1
        fi
        ;;
    start-bg)
        if check_port; then
            # Silent success if already running
            echo -e "${GREEN}[SSM Tunnel] Tunnel is already active.${NC}"
        else
            start_tunnel
        fi
        ;;
    stop)
        stop_tunnel
        ;;
    *)
        echo "Usage: $0 {check|start-bg|stop} [ENV]"
        exit 1
        ;;
esac
