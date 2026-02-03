#!/bin/bash
# =============================================================================
# Pre-Destroy Hook for Rancher/K8s Stacks
# Description: Modularized cleanup for AWS resources and K8s components
# =============================================================================

set -uo pipefail

# -----------------------------------------------------------------------------
# 1. Environment & Logging Setup
# -----------------------------------------------------------------------------
STACK="${1:-}"
RANCHER_STACKS="55-rancher 55-bootstrap 50-rke2"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export LOG_FILE="${ROOT_DIR}/logs/terraform/destroy-${STACK:-unknown}-$(date +%Y%m%d).log"

# Load common logging utility
if [[ -f "${ROOT_DIR}/scripts/common/logging.sh" ]]; then
    source "${ROOT_DIR}/scripts/common/logging.sh"
else
    ok() { echo -e "  \033[32m✓\033[0m $*"; }
    warn() { echo -e "  \033[33m!\033[0m $*"; }
    info() { echo -e "  \033[2m$*\033[0m"; }
    header() { echo -e "\n\033[1;36m>>> $*\033[0m"; }
fi

# Exit early if not a target stack
if ! echo "$RANCHER_STACKS" | grep -qw "$STACK"; then
  exit 0
fi

# Configuration
export KUBECONFIG="${HOME}/.kube/config-rke2-${ENV:-dev}"
CLUSTER_NAME="meta-${ENV:-dev}-k8s"

# -----------------------------------------------------------------------------
# 2. Functional Modules
# -----------------------------------------------------------------------------

# A. Load Balancer Cleanup
cleanup_lbs() {
    local cluster_tag="kubernetes.io/cluster/${CLUSTER_NAME}"
    info "Searching for orphaned Load Balancers (Tag: ${cluster_tag})..."
    
    local lbs
    lbs=$(aws elbv2 describe-load-balancers --query "LoadBalancers[*].LoadBalancerArn" --output text 2>/dev/null || echo "")
    
    local found=false
    for arn in $lbs; do
        if aws elbv2 describe-tags --resource-arns "$arn" --query "TagDescriptions[0].Tags[?Key=='${cluster_tag}'].Value" --output text | grep -qE "owned|shared"; then
            info "  -> Found orphaned LB: ${arn##*/}. Deleting..."
            aws elbv2 delete-load-balancer --load-balancer-arn "$arn"
            found=true
        fi
    done
    [[ "$found" == "false" ]] && info "  -> No orphaned Load Balancers found."
}

# B. ENI Cleanup for specific Security Group
cleanup_enis() {
    local sg_id="$1"
    [[ -z "$sg_id" || "$sg_id" == "None" ]] && return
    
    info "Targeting dependent ENIs for SG: $sg_id..."
    local enis
    enis=$(aws ec2 describe-network-interfaces --filters Name=group-id,Values="$sg_id" --query "NetworkInterfaces[*].[NetworkInterfaceId,Status,Description]" --output text 2>/dev/null || echo "")
    
    if [[ -n "$enis" ]]; then
        echo "$enis" | while read -r id status desc; do
            info "     - $id [$status]: $desc"
            if [[ "$desc" == *"ELB"* || "$desc" == *"Interface for LB"* || "$desc" == *"kubernetes.io/cluster/${CLUSTER_NAME}"* ]]; then
                info "     -> Attempting forced cleanup for $id..."
                local attach_id
                attach_id=$(aws ec2 describe-network-interfaces --network-interface-ids "$id" --query "NetworkInterfaces[0].Attachment.AttachmentId" --output text 2>/dev/null || echo "None")
                if [[ -n "$attach_id" && "$attach_id" != "None" ]]; then
                    aws ec2 detach-network-interface --attachment-id "$attach_id" --force 2>/dev/null || true
                    sleep 2
                fi
                aws ec2 delete-network-interface --network-interface-id "$id" 2>/dev/null && ok "        ✓ Deleted." || warn "        ! Still busy."
            fi
        done
    else
        info "  -> No blocking ENIs found."
    fi
}

# C. Purge Cross-SG References
purge_sg_references() {
    local sg_id="$1"
    [[ -z "$sg_id" || "$sg_id" == "None" ]] && return
    
    info "Checking for cross-SG references to $sg_id..."
    local sgs_ingress sgs_egress referencing_sgs
    sgs_ingress=$(aws ec2 describe-security-groups --filters "Name=ip-permission.group-id,Values=$sg_id" --query "SecurityGroups[*].GroupId" --output text 2>/dev/null || echo "")
    sgs_egress=$(aws ec2 describe-security-groups --filters "Name=egress.ip-permission.group-id,Values=$sg_id" --query "SecurityGroups[*].GroupId" --output text 2>/dev/null || echo "")
    referencing_sgs=$(echo "$sgs_ingress $sgs_egress" | tr ' ' '\n' | grep "^sg-" | grep -v "$sg_id" | sort -u || echo "")
    
    if [[ -n "$referencing_sgs" ]]; then
        warn "  -> Detected blocking cross-SG references. Purging rules..."
        for ref_sg in $referencing_sgs; do
            local ref_name
            ref_name=$(aws ec2 describe-security-groups --group-ids "$ref_sg" --query "SecurityGroups[0].GroupName" --output text 2>/dev/null || echo "Unknown")
            info "     -> Revoking rules in $ref_name ($ref_sg)..."
            
            # Ingress
            local in_p
            in_p=$(aws ec2 describe-security-groups --group-ids "$ref_sg" --query "SecurityGroups[0].IpPermissions[?UserIdGroupPairs[?GroupId=='$sg_id']]" --output json 2>/dev/null)
            if [[ "$in_p" != "[]" && -n "$in_p" ]]; then
                aws ec2 revoke-security-group-ingress --group-id "$ref_sg" --ip-permissions "$in_p" 2>/dev/null && ok "        ✓ Ingress revoked."
            fi
            
            # Egress
            local ex_p
            ex_p=$(aws ec2 describe-security-groups --group-ids "$ref_sg" --query "SecurityGroups[0].IpPermissionsEgress[?UserIdGroupPairs[?GroupId=='$sg_id']]" --output json 2>/dev/null)
            if [[ "$ex_p" != "[]" && -n "$ex_p" ]]; then
                aws ec2 revoke-security-group-egress --group-id "$ref_sg" --ip-permissions "$ex_p" 2>/dev/null && ok "        ✓ Egress revoked."
            fi
        done
    fi
}

# D. Kubectl-based Resource Cleanup
cleanup_k8s_resources() {
    info "Starting Kubectl-based resource cleanup..."
    
    # Start tunnel if utility exists
    [[ -f "${ROOT_DIR}/scripts/common/tunnel.sh" ]] && "${ROOT_DIR}/scripts/common/tunnel.sh" start-bg "${ENV:-dev}"

    # Remove Webhooks (often block namespace deletion)
    kubectl delete mutatingwebhookconfiguration rancher.cattle.io --ignore-not-found 2>/dev/null || true
    kubectl delete validatingwebhookconfiguration rancher.cattle.io --ignore-not-found 2>/dev/null || true
    
    # Delete LB services
    local svcs
    svcs=$(kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}' 2>/dev/null || echo "")
    if [[ -n "$svcs" ]]; then
        for lb in $svcs; do
            info "    -> Deleting K8s Service: $lb"
            kubectl delete svc -n "${lb%/*}" "${lb#*/}" --wait=false &>/dev/null
        done
        sleep 3
    fi
    
    # Uninstall core components if not just RKE2
    if [[ "$STACK" != "50-rke2" ]]; then
        helm uninstall rancher -n cattle-system 2>/dev/null || true
        helm uninstall cert-manager -n cert-manager 2>/dev/null || true
        kubectl delete namespace cattle-system cert-manager --ignore-not-found --timeout=5s --wait=false 2>/dev/null || true
    fi
}

# E. DNS Records (via external-dns)
cleanup_dns() {
    header "Cleanup: Flashing DNS Records (via external-dns)"
    if ! command -v kubectl &> /dev/null; then
        warn "kubectl not found. Skipping DNS flush."
        return
    fi

    # external-dns가 동작 중인지 확인
    if ! kubectl get pods -n kube-system -l app.kubernetes.io/name=external-dns &> /dev/null; then
        warn "external-dns not running. DNS records might remain orphaned."
        return
    fi

    info "Deleting all Ingress resources to trigger external-dns removal..."
    # --wait=false를 사용하지 않아 삭제가 전파될 시간을 벌어줌
    kubectl delete ingress --all -A --timeout=30s || true
    
    info "Waiting for DNS records to propagate deletion..."
    sleep 10
}

# -----------------------------------------------------------------------------
# 3. Execution Flow
# -----------------------------------------------------------------------------
header "Commencing Pre-destroy Cleanup for $STACK"

# AWS side cleanup (Always possible if CLI auth works)
cleanup_lbs

if [[ "$STACK" == "50-rke2" ]]; then
    # Resolve node SG for deep dependency purge
    NODE_SG_ID=$(terraform -chdir="stacks/${ENV:-dev}/50-rke2" output -raw nodes_security_group_id 2>/dev/null | grep "^sg-" || \
                 aws ec2 describe-security-groups --filters "Name=tag:Name,Values=${ENV:-dev}-meta-k8s-common-sg" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "")
    
    if [[ -n "$NODE_SG_ID" && "$NODE_SG_ID" != "None" ]]; then
        cleanup_enis "$NODE_SG_ID"
        purge_sg_references "$NODE_SG_ID"
    fi
fi

# K8s side cleanup (Only if Control Plane is up)
if aws ec2 describe-instances --filters "Name=tag:Name,Values=${ENV:-dev}-meta-k8s-cp-*" "Name=instance-state-name,Values=running" --query "Reservations[].Instances[].InstanceId" --output text | grep -q "i-"; then
    cleanup_k8s_resources
else
    warn "Control Plane unreachable. Skipping K8s resource cleanup."
fi

ok "Pre-destroy cleanup completed for $STACK"
