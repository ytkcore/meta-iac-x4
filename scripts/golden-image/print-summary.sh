#!/bin/bash
# =============================================================================
# Golden Image Configuration Summary
# Displays formatted summary after 10-golden-image apply
# =============================================================================

set -e

ENV=${1:-dev}
STACK_DIR="stacks/${ENV}/10-golden-image"

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Icons
CHECK="✅"
CROSS="❌"
WARNING="⚠️"
PACKAGE="📦"
WRENCH="🔧"
CLIPBOARD="📋"
BOOK="📖"

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

print_header() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}          ${GREEN}Golden Image Configuration Summary${NC}                  ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

get_output() {
    local key=$1
    cd "$STACK_DIR" && terraform output -raw "$key" 2>/dev/null || echo "N/A"
}

get_output_json() {
    local key=$1
    cd "$STACK_DIR" && terraform output -json "$key" 2>/dev/null || echo "{}"
}

bool_icon() {
    if [[ "$1" == "true" ]]; then
        echo -e "${CHECK} ${GREEN}Enabled${NC}"
    else
        echo -e "${CROSS} ${RED}Disabled${NC}"
    fi
}

# -----------------------------------------------------------------------------
# Main Output
# -----------------------------------------------------------------------------

print_header

# Base Image Info
echo -e "${PACKAGE} ${BLUE}Base Image${NC}"
BASE_AMI=$(get_output "base_ami_id")
GOLDEN_AMI=$(get_output "golden_ami_id")
GOLDEN_NAME=$(get_output "golden_ami_name")

echo "   OS: Amazon Linux 2023"
echo "   Base AMI: ${GRAY}${BASE_AMI}${NC}"

if [[ "$GOLDEN_AMI" != "N/A" && "$GOLDEN_AMI" != "" ]]; then
    echo -e "   ${GREEN}Golden AMI: ${GOLDEN_AMI}${NC}"
    echo "   Name: ${GOLDEN_NAME}"
else
    echo -e "   ${YELLOW}Golden AMI: Not built yet (run 'make build-ami')${NC}"
fi

echo ""

# Component Status Table
echo -e "${WRENCH} ${BLUE}Component Status${NC}"
echo ""

# Get configuration from Terraform
CONFIG=$(get_output_json "golden_image_config")

# Table header
printf "   %-25s %-15s %-15s\n" "Component" "Installed" "Enabled (Default)"
printf "   %-25s %-15s %-15s\n" "─────────────────────────" "─────────────" "─────────────────"

# SSH
SSH_PORT=$(echo "$CONFIG" | jq -r '.ssh.port // 22')
SSH_INSTALLED=$(echo "$CONFIG" | jq -r '.ssh.port != null' 2>/dev/null && echo "true" || echo "true")
printf "   %-25s " "SSH (Port: ${SSH_PORT})"
echo -ne "${CHECK} Yes         "
echo -e "${CHECK} ${GREEN}Yes${NC}"

# Docker
DOCKER_INSTALLED=$(echo "$CONFIG" | jq -r '.docker.installed // false')
DOCKER_ENABLED=$(echo "$CONFIG" | jq -r '.docker.enabled // false')
printf "   %-25s " "Docker"
if [[ "$DOCKER_INSTALLED" == "true" ]]; then
    echo -ne "${CHECK} Yes         "
else
    echo -ne "${CROSS} No          "
fi
if [[ "$DOCKER_ENABLED" == "true" ]]; then
    echo -e "${CHECK} ${GREEN}Yes${NC}"
else
    echo -e "${CROSS} ${RED}No${NC}"
fi

# Docker Compose
DC_INSTALLED=$(echo "$CONFIG" | jq -r '.docker_compose.installed // false')
DC_VERSION=$(echo "$CONFIG" | jq -r '.docker_compose.version // "N/A"')
printf "   %-25s " "Docker Compose"
if [[ "$DC_INSTALLED" == "true" ]]; then
    echo -ne "${CHECK} Yes         "
else
    echo -ne "${CROSS} No          "
fi
echo -e "${GRAY}N/A${NC}"

# SSM Agent
SSM_INSTALLED=$(echo "$CONFIG" | jq -r '.ssm_agent.installed // false')
SSM_ENABLED=$(echo "$CONFIG" | jq -r '.ssm_agent.enabled // false')
printf "   %-25s " "SSM Agent"
if [[ "$SSM_INSTALLED" == "true" ]]; then
    echo -ne "${CHECK} Yes         "
else
    echo -ne "${CROSS} No          "
fi
if [[ "$SSM_ENABLED" == "true" ]]; then
    echo -e "${CHECK} ${GREEN}Yes (Always)${NC}"
else
    echo -e "${CROSS} ${RED}No${NC}"
fi

# CloudWatch Agent
CW_INSTALLED=$(echo "$CONFIG" | jq -r '.cloudwatch_agent.installed // false')
CW_ENABLED=$(echo "$CONFIG" | jq -r '.cloudwatch_agent.enabled // false')
printf "   %-25s " "CloudWatch Agent"
if [[ "$CW_INSTALLED" == "true" ]]; then
    echo -ne "${CHECK} Yes         "
else
    echo -ne "${CROSS} No          "
fi
if [[ "$CW_ENABLED" == "true" ]]; then
    echo -e "${CHECK} ${GREEN}Yes${NC}"
else
    echo -e "${CROSS} ${RED}No${NC} ${GRAY}(Cost opt)${NC}"
fi

# Teleport Agent
TP_INSTALLED=$(echo "$CONFIG" | jq -r '.teleport_agent.installed // false')
TP_ENABLED=$(echo "$CONFIG" | jq -r '.teleport_agent.enabled // false')
printf "   %-25s " "Teleport Agent"
if [[ "$TP_INSTALLED" == "true" ]]; then
    echo -ne "${CHECK} Yes         "
else
    echo -ne "${CROSS} No          "
fi
if [[ "$TP_ENABLED" == "true" ]]; then
    echo -e "${CHECK} ${GREEN}Yes${NC}"
else
    echo -e "${WARNING} ${YELLOW}Stack-controlled${NC}"
fi

# AWS CLI (항상 설치됨, 버전 정보는 하드코딩)
printf "   %-25s " "AWS CLI v2"
echo -ne "${CHECK} Yes         "
echo -e "${GRAY}N/A${NC}"

# SELinux
SELINUX_ENABLED=$(echo "$CONFIG" | jq -r '.selinux.enabled // false')
SELINUX_MODE=$(echo "$CONFIG" | jq -r '.selinux.mode // "disabled"')
printf "   %-25s " "SELinux"
if [[ "$SELINUX_ENABLED" == "true" ]]; then
    echo -ne "${CHECK} Yes         "
    if [[ "$SELINUX_MODE" == "enforcing" ]]; then
        echo -e "${CHECK} ${GREEN}Enforcing${NC}"
    else
        echo -e "${WARNING} ${YELLOW}${SELINUX_MODE^}${NC}"
    fi
else
    echo -ne "${CROSS} No          "
    echo -e "${CROSS} ${RED}Disabled${NC}"
fi

echo ""

# Documentation Reference
echo -e "${BOOK} ${BLUE}Documentation${NC}"
echo "   Specification: ${GRAY}docs/infrastructure/golden-image-specification.md${NC}"
echo "   Optimization: ${GRAY}docs/access-control/golden-image-optimization-strategy.md${NC}"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
