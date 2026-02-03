#!/bin/bash
# =============================================================================
# Force Cleanup Script for AWS Resources
# Description: Emergency cleanup for orphaned resources with prefix matching.
# Usage: ./force-cleanup.sh <ENV> <PROJECT> [--execute]
# =============================================================================

set -uo pipefail

# -----------------------------------------------------------------------------
# 1. Environment & Logging Setup
# -----------------------------------------------------------------------------
ENV="${1:-}"
PROJECT="${2:-}"
EXECUTE="${3:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load common logging utility
if [[ -f "${ROOT_DIR}/scripts/common/logging.sh" ]]; then
    source "${ROOT_DIR}/scripts/common/logging.sh"
else
    ok() { echo -e "  \033[32m✓\033[0m $*"; }
    warn() { echo -e "  \033[33m!\033[0m $*"; }
    info() { echo -e "  \033[2m$*\033[0m"; }
    header() { echo -e "\n\033[1;36m>>> $*\033[0m"; }
    err() { echo -e "  \033[31m✗\033[0m $*" >&2; }
fi

if [[ -z "$ENV" || -z "$PROJECT" ]]; then
  err "Usage: $0 <ENV> <PROJECT> [--execute]"
  exit 1
fi

PREFIX="${ENV}-${PROJECT}"
DRY_RUN=true
if [[ "$EXECUTE" == "--execute" ]]; then
    DRY_RUN=false
    checkpoint "CAUTION: EXECUTION MODE ENABLED for prefix: $PREFIX"
else
    header "DRY RUN MODE: No resources will be deleted (Prefix: $PREFIX)"
fi

# Helper for conditional AWS execution
run_aws() {
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] $*"
    else
        info "[EXECUTE] $*"
        "$@" || warn "  ! Command failed (continuing...)"
    fi
}

# -----------------------------------------------------------------------------
# 2. Functional Modules
# -----------------------------------------------------------------------------

# A. IAM Roles & Profiles
cleanup_iam() {
    header "Cleanup: IAM Roles & Profiles"
    local roles
    roles=$(aws iam list-roles --query "Roles[?starts_with(RoleName, '${PREFIX}')].RoleName" --output text 2>/dev/null || echo "")
    
    for role in $roles; do
        [[ "$role" == "None" || -z "$role" ]] && continue
        info "Processing Role: $role"

        # Detach Managed Policies
        local policies
        policies=$(aws iam list-attached-role-policies --role-name "$role" --query "AttachedPolicies[].PolicyArn" --output text 2>/dev/null || echo "")
        for policy in $policies; do
            [[ "$policy" == "None" ]] && continue
            run_aws aws iam detach-role-policy --role-name "$role" --policy-arn "$policy"
        done

        # Delete Inline Policies
        local inlines
        inlines=$(aws iam list-role-policies --role-name "$role" --query "PolicyNames[]" --output text 2>/dev/null || echo "")
        for policy in $inlines; do
            [[ "$policy" == "None" ]] && continue
            run_aws aws iam delete-role-policy --role-name "$role" --policy-name "$policy"
        done

        # Remove from Instance Profiles
        local profiles
        profiles=$(aws iam list-instance-profiles-for-role --role-name "$role" --query "InstanceProfiles[].InstanceProfileName" --output text 2>/dev/null || echo "")
        for profile in $profiles; do
            [[ "$profile" == "None" ]] && continue
            run_aws aws iam remove-role-from-instance-profile --instance-profile-name "$profile" --role-name "$role"
        done

        run_aws aws iam delete-role --role-name "$role"
    done
}

# B. ELB & Target Groups
cleanup_load_balancing() {
    header "Cleanup: Load Balancers & Target Groups"
    local lbs
    lbs=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?starts_with(LoadBalancerName, '${PREFIX}')].LoadBalancerArn" --output text 2>/dev/null || echo "")
    for lb in $lbs; do
        [[ "$lb" == "None" || -z "$lb" ]] && continue
        info "Removing LB: ${lb##*/}"
        run_aws aws elbv2 modify-load-balancer-attributes --load-balancer-arn "$lb" --attributes Key=deletion_protection.enabled,Value=false
        run_aws aws elbv2 delete-load-balancer --load-balancer-arn "$lb"
    done

    local tgs
    tgs=$(aws elbv2 describe-target-groups --query "TargetGroups[?starts_with(TargetGroupName, '${PREFIX}')].TargetGroupArn" --output text 2>/dev/null || echo "")
    for tg in $tgs; do
        [[ "$tg" == "None" || -z "$tg" ]] && continue
        info "Deleting Target Group: ${tg##*/}"
        run_aws aws elbv2 delete-target-group --target-group-arn "$tg"
    done
}

# C. EC2 Instances
cleanup_ec2() {
    header "Cleanup: EC2 Instances"
    local instances
    instances=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${PREFIX}*" "Name=instance-state-name,Values=running,stopped,stopping,pending" --query "Reservations[].Instances[].InstanceId" --output text 2>/dev/null || echo "")
    
    if [[ -n "$instances" && "$instances" != "None" ]]; then
        info "Terminating Instances: $instances"
        for inst in $instances; do
            run_aws aws ec2 modify-instance-attribute --instance-id "$inst" --no-disable-api-termination
            run_aws aws ec2 terminate-instances --instance-ids "$inst"
        done
        [[ "$DRY_RUN" == "false" ]] && info "Waiting for termination..." && aws ec2 wait instance-terminated --instance-ids $instances 2>/dev/null || true
    else
        info "No active instances found for this prefix."
    fi
}

# D. Security Groups (Advanced Purge)
cleanup_security_groups() {
    header "Cleanup: Security Groups (Advanced Rule Purge)"
    local sgs
    sgs=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${PREFIX}*" --query "SecurityGroups[].GroupId" --output text 2>/dev/null || echo "")
    
    for sg in $sgs; do
        [[ "$sg" == "None" || -z "$sg" ]] && continue
        info "Found SG: $sg. Purging rules to resolve dependencies..."
        
        # Revoke Ingress
        local in_p
        in_p=$(aws ec2 describe-security-groups --group-ids "$sg" --query "SecurityGroups[0].IpPermissions" --output json 2>/dev/null)
        if [[ "$in_p" != "[]" && -n "$in_p" ]]; then
            run_aws aws ec2 revoke-security-group-ingress --group-id "$sg" --ip-permissions "$in_p"
        fi
        
        # Revoke Egress
        local ex_p
        ex_p=$(aws ec2 describe-security-groups --group-ids "$sg" --query "SecurityGroups[0].IpPermissionsEgress" --output json 2>/dev/null)
        if [[ "$ex_p" != "[]" && -n "$ex_p" ]]; then
            # 'All Outbound' rule (protocol -1, 0.0.0.0/0) often needs special handling or just skip if standard
            run_aws aws ec2 revoke-security-group-egress --group-id "$sg" --ip-permissions "$ex_p"
        fi
    done

    # Final deletion attempt (with retries for slow AWS API)
    for sg in $sgs; do
        [[ "$sg" == "None" || -z "$sg" ]] && continue
        info "Attempting deletion of SG: $sg"
        if [[ "$DRY_RUN" == "false" ]]; then
            for i in {1..3}; do
                aws ec2 delete-security-group --group-id "$sg" 2>/dev/null && ok "  ✓ Deleted." && break || warn "  ! Attempt $i failed (busy), retrying..."
                sleep 2
            done
        else
            info "  [DRY RUN] Would delete SG: $sg"
        fi
    done
}

# E. Route53 DNS (Orphaned TXT records)
cleanup_dns() {
    header "Cleanup: Route53 Orphaned Records"
    local zone_id
    zone_id=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='unifiedmeta.net.'].Id" --output text 2>/dev/null || echo "")
    
    if [[ -z "$zone_id" || "$zone_id" == "None" ]]; then
        warn "Hosted Zone unifiedmeta.net not found. Skipping DNS cleanup."
        return
    fi
    
    info "Scanning for orphaned external-dns TXT records in $zone_id..."
    
    # external-dns bootstrap owner로 생성된 TXT 레코드 조회 (a-접두사 포함)
    local records
    records=$(aws route53 list-resource-record-sets --hosted-zone-id "$zone_id" \
        --query "ResourceRecordSets[?Type=='TXT' && contains(ResourceRecords[0].Value, 'external-dns-bootstrap') && (starts_with(Name, 'a-'))]" \
        --output json 2>/dev/null)
        
    if [[ "$records" == "[]" || -z "$records" ]]; then
        ok "No orphaned TXT records found."
        return
    fi
    
    echo "$records" | jq -c '.[]' | while read -r record; do
        local name type value ttl
        name=$(echo "$record" | jq -r '.Name')
        type=$(echo "$record" | jq -r '.Type')
        value=$(echo "$record" | jq -r '.ResourceRecords[0].Value')
        ttl=$(echo "$record" | jq -r '.TTL')
        
        # 대응되는 서비스 레코드(A/CNAME)가 있는지 확인
        local svc_name="${name#a-}"
        local svc_exists
        svc_exists=$(aws route53 list-resource-record-sets --hosted-zone-id "$zone_id" --query "ResourceRecordSets[?Name=='$svc_name']" --output text 2>/dev/null)
        
        if [[ -z "$svc_exists" || "$svc_exists" == "None" || "$svc_exists" == "[]" ]]; then
            warn "Orphan detected: $name (Service record $svc_name is missing)"
            
            # Deletion JSON format
            local batch=$(cat <<EOF
{
  "Comment": "Force cleanup of orphaned external-dns TXT record",
  "Changes": [
    {
      "Action": "DELETE",
      "ResourceRecordSet": {
        "Name": "$name",
        "Type": "$type",
        "TTL": $ttl,
        "ResourceRecords": [{ "Value": $value }]
      }
    }
  ]
}
EOF
)
            run_aws aws route53 change-resource-record-sets --hosted-zone-id "$zone_id" --change-batch "$batch"
        fi
    done
}

# -----------------------------------------------------------------------------
# 3. Execution Flow
# -----------------------------------------------------------------------------
cleanup_ec2
cleanup_load_balancing
cleanup_iam
cleanup_security_groups
cleanup_dns

ok "Force Cleanup Scan Complete for $PREFIX"
