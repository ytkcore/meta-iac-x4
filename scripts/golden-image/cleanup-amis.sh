#!/bin/bash
# =============================================================================
# Golden Image Cleanup Script
# Deregisters Golden Image AMIs before stack destroy
# =============================================================================

set -euo pipefail

STACK="${1:-}"
AMI_NAME_PATTERN="meta-golden-image-al2023-*"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

cleanup_golden_images() {
    log_warn "Cleaning up Golden Image AMIs..."
    
    # Get all Golden Image AMIs
    local amis=$(aws ec2 describe-images \
        --owners self \
        --filters "Name=name,Values=$AMI_NAME_PATTERN" \
        --query 'Images[].ImageId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$amis" ]]; then
        log_warn "No Golden Image AMIs found to clean up"
        return 0
    fi
    
    for ami in $amis; do
        log_warn "Deregistering AMI: $ami"
        
        # Get associated snapshots before deregistering
        local snapshots=$(aws ec2 describe-images \
            --image-ids "$ami" \
            --query 'Images[].BlockDeviceMappings[].Ebs.SnapshotId' \
            --output text 2>/dev/null || echo "")
        
        # Deregister AMI
        if aws ec2 deregister-image --image-id "$ami" 2>/dev/null; then
            log_warn "Deregistered AMI: $ami"
            
            # Delete associated snapshots
            for snapshot in $snapshots; do
                if [[ -n "$snapshot" ]]; then
                    log_warn "Deleting snapshot: $snapshot"
                    aws ec2 delete-snapshot --snapshot-id "$snapshot" 2>/dev/null || true
                fi
            done
        else
            log_error "Failed to deregister AMI: $ami"
        fi
    done
}

# Main
main() {
    if [[ "$STACK" == "10-golden-image" ]]; then
        cleanup_golden_images
    fi
}

main "$@"
