#!/usr/bin/env bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Directory paths
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV="${ENV:-dev}"
ENV_DIR="stacks/${ENV}"
TFVARS_FILE="${ENV_DIR}/env.tfvars"

echo -e "${BLUE}=== [Init] Initializing Environment: ${ENV} ===${NC}"

# 1. Create directory if not exists
if [ ! -d "${ENV_DIR}" ]; then
  echo -e "${YELLOW}Creating directory: ${ENV_DIR}${NC}"
  mkdir -p "${ENV_DIR}"
fi

# 2. Check if env.tfvars exists
if [ -f "${TFVARS_FILE}" ]; then
  echo -e "${GREEN}Found existing ${TFVARS_FILE}.${NC}"
  read -p "Do you want to re-configure it? (y/N) " RECONFIG
  if [[ ! "$RECONFIG" =~ ^[Yy]$ ]]; then
    echo "Skipping configuration."
    exit 0
  fi
fi

# 3. Interactive Configuration (Minimal)
echo -e "\n${BLUE}--- Configuration Wizard ---${NC}"

# Function to get input with default
get_input() {
  local prompt="$1"
  local default="$2"
  local var_name="$3"
  
  read -p "${prompt} [${default}]: " input
  input="${input:-$default}"
  eval "$var_name=\"$input\""
}

# (1) Base Domain (Required)
while true; do
  get_input "Enter Base Domain" "unifiedmeta.net" BASE_DOMAIN
  if [ -n "$BASE_DOMAIN" ]; then
    break
  else
    echo -e "${RED}Base Domain is required.${NC}"
  fi
done

# (2) Project Name
get_input "Enter Project Name" "meta" PROJECT

# (3) S3 State Bucket (Smart Default)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "000000")
DEFAULT_BUCKET="${PROJECT}-${ENV}-tfstate-${AWS_ACCOUNT_ID}"
get_input "Enter S3 State Bucket Name" "${DEFAULT_BUCKET}" STATE_BUCKET

echo -e "${YELLOW}Creating ${TFVARS_FILE} with minimal configuration...${NC}"

# Generate env.tfvars (Minimal)
cat > "${TFVARS_FILE}" <<EOF
# -----------------------------------------------------------------------------
# Essential Configuration
# -----------------------------------------------------------------------------
base_domain  = "${BASE_DOMAIN}"
project      = "${PROJECT}"
env          = "${ENV}"

# -----------------------------------------------------------------------------
# Optional Overrides (Uncomment to change defaults)
# -----------------------------------------------------------------------------
# region = "ap-northeast-2"
# azs    = ["ap-northeast-2a", "ap-northeast-2c"]

# db_instance_type   = "t3.large"
# postgres_image_tag = "18.1"
EOF

# Generate backend.hcl (Terraform native format)
BACKEND_HCL="${ENV_DIR}/backend.hcl"
cat > "${BACKEND_HCL}" <<EOF
bucket = "${STATE_BUCKET}"
region = "ap-northeast-2"
EOF

echo -e "\n${GREEN}Configuration Saved to ${TFVARS_FILE} and ${BACKEND_HCL}${NC}"
echo -e "NOTE: Advanced settings (instance types, versions, etc.) use sensible defaults."
echo -e "You can override them in ${TFVARS_FILE} if needed.\n"

# 4. Smart Backend Initialization
echo -e "${BLUE}--- Backend Initialization ---${NC}"
echo "Checking if S3 backend bucket exists..."

# Check if bucket exists
if aws s3api head-bucket --bucket "${STATE_BUCKET}" 2>/dev/null; then
  echo -e "${GREEN}✓ Backend bucket '${STATE_BUCKET}' already exists.${NC}"
else
  echo -e "${YELLOW}⚠ Backend bucket '${STATE_BUCKET}' does not exist.${NC}"
  read -p "Do you want to create it now? (Y/n) " CREATE_BACKEND
  
  if [[ ! "$CREATE_BACKEND" =~ ^[Nn]$ ]]; then
    echo "Creating S3 backend bucket..."
    STATE_BUCKET="${STATE_BUCKET}" STATE_REGION="ap-northeast-2" \
      "${ROOT_DIR}/scripts/common/backend-bootstrap.sh"
    
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}✓ Backend bucket created successfully!${NC}"
    else
      echo -e "${RED}✗ Failed to create backend bucket.${NC}"
      echo "Please check AWS credentials and try again."
      exit 1
    fi
  else
    echo -e "${YELLOW}Skipping backend creation.${NC}"
    echo "You'll need to create it manually before running terraform."
  fi
fi

echo -e "\n${GREEN}=== Init Complete ===${NC}"
echo "Next Steps:"
echo "  1. make plan  STACK=00-network"
echo "  2. make apply STACK=00-network"
