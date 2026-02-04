#!/bin/bash
# =============================================================================
# Post-Apply Hook
# Stack-specific actions to run after successful terraform apply
# =============================================================================

STACK=$1
ENV=${ENV:-dev}

case "$STACK" in
    "10-golden-image")
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        bash scripts/golden-image/print-summary.sh "$ENV"
        ;;
    
    # Add more stack-specific hooks here as needed
    # "50-rke2")
    #     bash scripts/rke2/post-apply-checks.sh "$ENV"
    #     ;;
esac
