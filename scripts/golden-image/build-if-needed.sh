#!/bin/bash
# =============================================================================
# Golden Image Build Wrapper
# Checks if AMI exists before building
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_IF_NEEDED="${BUILD_IF_NEEDED:-true}"
AMI_NAME_PATTERN="${AMI_NAME_PATTERN:-meta-golden-image-al2023-*}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_skip() { echo -e "${BLUE}[SKIP]${NC} $1"; }

# Check if Golden Image already exists
check_existing_ami() {
    log_info "Checking for existing Golden Image..."
    
    local ami_id=$(aws ec2 describe-images \
        --owners self \
        --filters "Name=name,Values=$AMI_NAME_PATTERN" "Name=state,Values=available" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text 2>/dev/null || echo "None")
    
    if [[ "$ami_id" != "None" && -n "$ami_id" ]]; then
        log_info "Found existing Golden Image: $ami_id"
        echo "$ami_id"
        return 0
    else
        log_info "No existing Golden Image found"
        return 1
    fi
}

# Main
main() {
    if [[ "$BUILD_IF_NEEDED" == "true" ]]; then
        if check_existing_ami > /dev/null 2>&1; then
            local existing_ami=$(check_existing_ami)
            log_skip "Golden Image already exists: $existing_ami"
            log_skip "Skipping Packer build (set BUILD_IF_NEEDED=false to force rebuild)"
            exit 0
        fi
    fi
    
    log_info "Building new Golden Image with Packer..."
    
    # Get VPC and Subnet from network stack
    log_info "Querying VPC and Subnet from network stack..."
    local vpc_id=$(terraform -chdir="stacks/${ENV:-dev}/00-network" output -raw vpc_id 2>/dev/null || echo "")
    local subnet_id=$(terraform -chdir="stacks/${ENV:-dev}/00-network" output -json subnet_ids_by_tier 2>/dev/null | jq -r '.common[0]' 2>/dev/null || echo "")
    
    if [[ -z "$vpc_id" || -z "$subnet_id" ]]; then
        log_warn "Could not retrieve VPC/Subnet from network stack"
        log_warn "Packer will attempt to use default VPC (may fail)"
    else
        log_info "Using VPC: $vpc_id, Subnet: $subnet_id"
        export PKR_VAR_vpc_id="$vpc_id"
        export PKR_VAR_subnet_id="$subnet_id"
    fi
    
    cd "$SCRIPT_DIR/../packer"
    exec ./build.sh build
}

main "$@"
