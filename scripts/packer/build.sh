#!/bin/bash
# =============================================================================
# Golden Image Build Script
# Usage: ./build.sh [options]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Defaults
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
PACKER_LOG="${PACKER_LOG:-0}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check prerequisites
check_prereqs() {
    log_info "Checking prerequisites..."
    
    if ! command -v packer &> /dev/null; then
        log_error "Packer is not installed. Install with: brew install packer"
        exit 1
    fi
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Use aws-vault or configure credentials."
        exit 1
    fi
    
    log_info "Prerequisites OK"
}

# Initialize Packer
init_packer() {
    log_info "Initializing Packer..."
    packer init golden-image.pkr.hcl
}

# Validate template
validate_template() {
    log_info "Validating Packer template..."
    packer validate golden-image.pkr.hcl
}

# Build image
build_image() {
    log_info "Building Golden Image..."
    
    local var_file=""
    if [[ -f "golden-image.auto.pkrvars.hcl" ]]; then
        var_file="-var-file=golden-image.auto.pkrvars.hcl"
    fi
    
    # Pass VPC/Subnet from environment if set
    local extra_vars=""
    if [[ -n "${PKR_VAR_vpc_id:-}" ]]; then
        extra_vars="$extra_vars -var vpc_id=$PKR_VAR_vpc_id"
    fi
    if [[ -n "${PKR_VAR_subnet_id:-}" ]]; then
        extra_vars="$extra_vars -var subnet_id=$PKR_VAR_subnet_id"
    fi
    
    PACKER_LOG=$PACKER_LOG packer build $var_file $extra_vars golden-image.pkr.hcl
    
    if [[ -f "manifest.json" ]]; then
        log_info "Build complete!"
        local ami_id=$(jq -r '.builds[-1].artifact_id' manifest.json | cut -d':' -f2)
        log_info "AMI ID: $ami_id"
        echo "$ami_id" > .last-ami-id
    fi
}

# Cleanup old AMIs (keep last N)
cleanup_old_amis() {
    local keep=${1:-3}
    log_info "Cleaning up old AMIs (keeping last $keep)..."
    
    local amis=$(aws ec2 describe-images \
        --owners self \
        --filters "Name=name,Values=meta-golden-image-al2023-*" \
        --query 'Images | sort_by(@, &CreationDate) | [:-'"$keep"'].ImageId' \
        --output text)
    
    for ami in $amis; do
        log_warn "Deregistering old AMI: $ami"
        aws ec2 deregister-image --image-id "$ami"
    done
}

# Main
main() {
    case "${1:-build}" in
        init)
            check_prereqs
            init_packer
            ;;
        validate)
            validate_template
            ;;
        build)
            check_prereqs
            init_packer
            validate_template
            build_image
            ;;
        cleanup)
            cleanup_old_amis "${2:-3}"
            ;;
        *)
            echo "Usage: $0 {init|validate|build|cleanup [keep_count]}"
            exit 1
            ;;
    esac
}

main "$@"
