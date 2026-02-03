#!/bin/bash
# =============================================================================
# Environment Initialization Script
# Usage: ENV=dev ./init-env.sh
# =============================================================================

set -uo pipefail

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
# Colors
if [ -t 1 ]; then
  GREEN='\033[32m'
  RED='\033[31m'
  YELLOW='\033[33m'
  CYAN='\033[36m'
  BOLD='\033[1m'
  DIM='\033[2m'
  NC='\033[0m'
else
  GREEN='' RED='' YELLOW='' CYAN='' BOLD='' DIM='' NC=''
fi

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------
ok()     { echo -e "  ${GREEN}✓${NC} $*"; }
fail()   { echo -e "  ${RED}✗${NC} $*"; }
warn()   { echo -e "  ${YELLOW}!${NC} $*"; }
info()   { echo -e "  ${DIM}$*${NC}"; }
header() { echo -e "\n${CYAN}${BOLD}[$1]${NC} $2"; }

aws_exec() {
  if [ -z "${AWS_VAULT:-}" ]; then
    aws-vault exec devops -- "$@"
  else
    "$@"
  fi
}

get_input() {
  local prompt="$1" default="$2" var_name="$3"
  local val
  read -r -p "${prompt} [${default}]: " val
  if [[ -z "$val" ]]; then
    val="$default"
  fi
  eval "$var_name=\"$val\""
  echo "  -> Selected: $val"
}

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV="${ENV:-dev}"
ENV_DIR="stacks/${ENV}"
TFVARS_FILE="${ENV_DIR}/env.tfvars"

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
echo -e "\n${BOLD}Environment Initialization: ${ENV}${NC}\n"

# Create directory
header 1 "Directory Setup"
if [[ ! -d "${ENV_DIR}" ]]; then
  mkdir -p "${ENV_DIR}"
  ok "Created ${ENV_DIR}"
else
  ok "Directory exists: ${ENV_DIR}"
fi

# Check if Packer is installed
if ! command -v packer &> /dev/null; then
  echo -e "  ${YELLOW}!${NC} Packer가 시스템에 설치되어 있지 않습니다."
  read -p "    지금 Packer를 설치하시겠습니까? (Y/n) " INSTALL_PACKER
  if [[ ! "$INSTALL_PACKER" =~ ^[Nn]$ ]]; then
    info "Packer 설치를 시작합니다 (brew install hashicorp/tap/packer)..."
    if brew tap hashicorp/tap && brew install hashicorp/tap/packer; then
      ok "Packer 설치 완료"
    else
      fail "Packer 설치 실패. 수동으로 설치해 주세요: brew tap hashicorp/tap && brew install hashicorp/tap/packer"
      exit 1
    fi
  else
    warn "Packer 설치를 건너뜁니다. 골든 이미지 빌드가 불가능할 수 있습니다."
    exit 1
  fi
fi

# Check existing config
if [[ -f "${TFVARS_FILE}" ]]; then
  ok "Found existing ${TFVARS_FILE}"
  read -p "Do you want to re-configure it? (y/N) " RECONFIG
  if [[ ! "$RECONFIG" =~ ^[Yy]$ ]]; then
    info "Skipping configuration"
    exit 0
  fi
fi

# Interactive configuration
header 2 "Configuration Wizard"

while true; do
  get_input "Enter Base Domain" "unifiedmeta.net" BASE_DOMAIN
  [[ -n "$BASE_DOMAIN" ]] && break
  fail "Base Domain is required"
  get_input "Enter Base Domain" "unifiedmeta.net" BASE_DOMAIN
  [[ -n "$BASE_DOMAIN" ]] && break
  fail "Base Domain is required"
done

get_input "Enter VPC CIDR" "10.0.0.0/16" VPC_CIDR

get_input "Enter Project Name" "meta" PROJECT

#AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "000000")
DEFAULT_BUCKET="${ENV}-${PROJECT}-tfstate"
get_input "Enter S3 State Bucket Name" "${DEFAULT_BUCKET}" STATE_BUCKET

DEFAULT_HARBOR_BUCKET="${ENV}-${PROJECT}-harbor-storage"
get_input "Enter Harbor S3 Bucket Name" "${DEFAULT_HARBOR_BUCKET}" HARBOR_BUCKET

DEFAULT_LONGHORN_BUCKET="${ENV}-${PROJECT}-longhorn-backup"
get_input "Enter Longhorn Backup S3 Bucket Name" "${DEFAULT_LONGHORN_BUCKET}" LONGHORN_BACKUP_BUCKET

# Smart SSH Key Detection
DEFAULT_SSH_KEY="~/.ssh/id_rsa"
if [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
  DEFAULT_SSH_KEY="~/.ssh/id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
   DEFAULT_SSH_KEY="~/.ssh/id_rsa"
fi

get_input "Enter GitOps Repo URL (SSH format)" "git@github.com:ytkcore/meta-iac-x4.git" GITOPS_REPO
get_input "Enter Local SSH Key Path" "${DEFAULT_SSH_KEY}" SSH_KEY_PATH

# Generate env.tfvars
header 3 "Generating Configuration"
cat > "${TFVARS_FILE}" <<EOF
# -----------------------------------------------------------------------------
# Essential Configuration
# -----------------------------------------------------------------------------
base_domain  = "${BASE_DOMAIN}"
project      = "${PROJECT}"
env          = "${ENV}"

# -----------------------------------------------------------------------------
# Remote State Configuration
# -----------------------------------------------------------------------------
state_bucket     = "${STATE_BUCKET}"
state_region     = "ap-northeast-2"
state_key_prefix = "iac"

# -----------------------------------------------------------------------------
# Network Topology
# -----------------------------------------------------------------------------
vpc_cidr = "${VPC_CIDR}"

# -----------------------------------------------------------------------------
# Storage & Backup Configuration
# -----------------------------------------------------------------------------
target_bucket_name = "${HARBOR_BUCKET}"
longhorn_backup_bucket = "${LONGHORN_BACKUP_BUCKET}"

# -----------------------------------------------------------------------------
# Optional Overrides (Uncomment to change defaults)
# -----------------------------------------------------------------------------
region = "ap-northeast-2"
azs    = ["ap-northeast-2a", "ap-northeast-2c"]

# db_instance_type   = "t3.large"
# postgres_image_tag = "18.1"

# -----------------------------------------------------------------------------
# Management & Security
# -----------------------------------------------------------------------------
enable_interface_endpoints = true
interface_services         = ["ssm", "ssmmessages", "ec2messages"]
interface_subnet_tiers     = ["common"]

# -----------------------------------------------------------------------------
# GitOps Configuration
# -----------------------------------------------------------------------------
enable_gitops_apps = true
gitops_apps_path   = "gitops-apps/bootstrap"
gitops_repo_url    = "${GITOPS_REPO}"
gitops_ssh_key_path = "${SSH_KEY_PATH}"
EOF
ok "Created ${TFVARS_FILE}"

# Generate backend.hcl
BACKEND_HCL="${ENV_DIR}/backend.hcl"
cat > "${BACKEND_HCL}" <<EOF
bucket = "${STATE_BUCKET}"
region = "ap-northeast-2"
EOF
ok "Created ${BACKEND_HCL}"

# Backend initialization
header 4 "Backend Initialization"
info "Checking if S3 backend bucket exists..."

# [FIX] Use aws_exec helper to avoid nested vault calls
if aws_exec aws s3api head-bucket --bucket "${STATE_BUCKET}" 2>/dev/null; then
  ok "Backend bucket '${STATE_BUCKET}' already exists"
else
  warn "Backend bucket '${STATE_BUCKET}' does not exist (or access denied)"
  read -p "Do you want to create it now? (Y/n) " CREATE_BACKEND
  
  if [[ ! "$CREATE_BACKEND" =~ ^[Nn]$ ]]; then
    info "Creating S3 backend bucket..."
    STATE_BUCKET="${STATE_BUCKET}" STATE_REGION="ap-northeast-2" \
      "${ROOT_DIR}/scripts/common/backend-bootstrap.sh"
    
    if [[ $? -eq 0 ]]; then
      ok "Backend bucket created successfully"
    else
      fail "Failed to create backend bucket"
      info "Please check AWS credentials and try again"
      exit 1
    fi
  else
    warn "Skipping backend creation"
    info "You'll need to create it manually before running terraform"
  fi
fi

# Summary
echo -e "\n${BOLD}Init Complete${NC}"
echo ""
info "Next Steps:"
info "  1. make plan  STACK=00-network"
info "  2. make apply STACK=00-network"
