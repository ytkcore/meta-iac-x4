#!/bin/bash
set -e

export ENV=${1:-dev}
TARGET_STACK=$2

PROJECT="meta"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

cd "$ROOT_DIR"

# Full list of stacks
ALL_STACKS=("00-network" "10-security" "20-endpoints" "30-bastion" "40-harbor" "50-rke2" "55-bootstrap" "55-rancher" "60-db")
NEED_TUNNEL=("55-bootstrap" "60-apps" "99-gitops")

# Determine which stacks to run
if [[ -n "$TARGET_STACK" ]]; then
    # Verify strict stack name
    if [[ ! " ${ALL_STACKS[*]} " =~ " ${TARGET_STACK} " ]]; then
        echo "❌ Error: '$TARGET_STACK' is not a valid stack name."
        echo "Valid stacks: ${ALL_STACKS[*]}"
        exit 1
    fi
     STACKS=("$TARGET_STACK")
else
     STACKS=("${ALL_STACKS[@]}")
fi

echo "================================================================================"
echo " 🚀 Starting Recovery Procedure (Env: $ENV)"
if [[ -n "$TARGET_STACK" ]]; then
    echo " 🎯 Target Stack: $TARGET_STACK"
else
    echo " 🎯 Target: ALL STACKS"
fi
echo "================================================================================"

# 0. Base Domain Check
./scripts/common/ensure-base-domain.sh "$ENV"

for STACK in "${STACKS[@]}"; do
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo " ▶ Processing Stack: $STACK"
    echo "--------------------------------------------------------------------------------"
    
    # 1. Start Tunnel if needed
    if [[ " ${NEED_TUNNEL[*]} " == *" $STACK "* ]]; then
         echo " [Tunnel] Starting SSM tunnel..."
         ./scripts/common/tunnel.sh start-bg "$ENV"
         sleep 2
    fi

    # 2. Run Import Script
    # Prepare TF_VAR_FILES
    VAR_OPTS="-var-file=../env.tfvars"
    if [[ -f "stacks/${ENV}/env.auto.tfvars" ]]; then
        VAR_OPTS="$VAR_OPTS -var-file=../env.auto.tfvars"
    fi
     
    # Config for 40-harbor
    EXTRA_OPTS=""
    if [[ "$STACK" == "40-harbor" ]]; then
         # Try parsing bucket from env.tfvars if it exists
         TF_VARS_PATH="stacks/${ENV}/env.tfvars"
         if [[ -f "$TF_VARS_PATH" ]]; then
             BUCKET_NAME=$(grep 'target_bucket_name' "$TF_VARS_PATH" | cut -d'=' -f2 | tr -d ' "')
         fi
         
         if [[ -n "$BUCKET_NAME" ]]; then
             # For recovery, we assume we want to manage the bucket.
             # So always set create_bucket=true.
             # Import script will import it if it exists.
             EXTRA_OPTS="-var=create_bucket=true"
         else
             echo " [Warn] 'target_bucket_name' not found in env.tfvars for 40-harbor"
         fi
    fi

    # Call import-stack.sh
    # Note: import-stack changed dir internally but it runs in subshell if we run it as executable
    ./scripts/terraform/import-stack.sh "$STACK" "$VAR_OPTS $EXTRA_OPTS"
    
    # 3. Terraform Plan (Verification)
    echo " [Plan] Running terraform plan..."
    
    # Go to stack dir
    pushd "stacks/${ENV}/${STACK}" > /dev/null
    
    # Ensure versions.tf
    if [ ! -f "versions.tf" ]; then
        ln -sf ../../../modules/common_versions.tf versions.tf
    fi
    
    # Config for 40-harbor (ALREADY DONE ABOVE)

    # Init & Plan
    terraform init -upgrade=false -reconfigure \
        -backend-config="../../../stacks/${ENV}/backend.hcl" \
        -backend-config="key=iac/${ENV}/${STACK}.tfstate" >/dev/null

    terraform plan $VAR_OPTS $EXTRA_OPTS -compact-warnings
    
    popd > /dev/null
    
    # Stop Tunnel if it was needed (optional, or keep it running? Makefile stops it usually only on stop command)
    # We leave it running for speed in loop? No, better safe.
    # Actually makefile tunnel-check starts it if not running.
done

echo ""
echo "================================================================================"
echo " ✅ Recovery Completed!"
echo "================================================================================"
