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

    "15-teleport")
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🔍 Checking Teleport Admin Invite Link..."
        
        # Get Instance ID (Assuming name contains 'teleport' and is running)
        INSTANCE_ID=$(aws ec2 describe-instances \
            --filters "Name=tag:Name,Values=*teleport*" "Name=instance-state-name,Values=running" \
            --query "Reservations[0].Instances[0].InstanceId" --output text)

        if [[ "$INSTANCE_ID" != "None" && -n "$INSTANCE_ID" ]]; then
            echo "   Target Instance: $INSTANCE_ID"
            echo "   Executing 'tctl users reset admin' via SSM..."
            
            # Send Command (Reset if exists, Add if not)
            CMD_ID=$(aws ssm send-command \
                --instance-ids "$INSTANCE_ID" \
                --document-name "AWS-RunShellScript" \
                --parameters 'commands=["sudo tctl users reset admin --ttl=1h || sudo tctl users add admin --roles=editor,access --logins=ec2-user,ubuntu --ttl=1h"]' \
                --query "Command.CommandId" --output text)
            
            # Wait for result (simple wait)
            sleep 3
            
            # Get Output
            OUTPUT=$(aws ssm get-command-invocation \
                --command-id "$CMD_ID" \
                --instance-id "$INSTANCE_ID" \
                --query "StandardOutputContent" --output text)
            
            if [[ -n "$OUTPUT" && "$OUTPUT" != "None" ]]; then
                echo "✅ Admin Invite Link Generated:"
                echo "$OUTPUT" | grep -o 'https://.*'
                echo ""
                echo "(Link valid for 1 hour)"
            else
                echo "⚠️  Could not retrieve invite link. Teleport might be starting up."
                echo "   Try manually: aws ssm start-session --target $INSTANCE_ID"
            fi
        else
            echo "⚠️  No running Teleport instance found."
        fi
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        ;;
    
    # Add more stack-specific hooks here as needed
    # "50-rke2")
    #     bash scripts/rke2/post-apply-checks.sh "$ENV"
    #     ;;
esac
