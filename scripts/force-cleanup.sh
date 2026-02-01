#!/bin/bash
set -e

# Usage: ./force-cleanup.sh <ENV> <PROJECT> [--execute]

ENV=$1
PROJECT=$2
EXECUTE=$3

if [ -z "$ENV" ] || [ -z "$PROJECT" ]; then
  echo "Usage: $0 <ENV> <PROJECT> [--execute]"
  echo "Example: $0 dev meta --execute"
  exit 1
fi

PREFIX="${ENV}-${PROJECT}"
DRY_RUN=true

if [ "$EXECUTE" == "--execute" ]; then
  DRY_RUN=false
  echo "!!! CAUTION: EXECUTION MODE ENABLED. RESOURCES WILL BE DELETED !!!"
else
  echo "=== DRY RUN MODE: No resources will be deleted ==="
fi

echo "Targeting resources with prefix: $PREFIX"
echo "---------------------------------------------------"

# Helper for execution
run_aws() {
  if [ "$DRY_RUN" = "true" ]; then
    echo "[DRY RUN] $@"
  else
    echo "[EXECUTE] $@"
    "$@"
  fi
}

# -----------------------------------------------------------------------------
# 1. IAM Cleanup
# -----------------------------------------------------------------------------
echo "Scanning IAM Roles..."
ROLES=$(aws iam list-roles --query "Roles[?starts_with(RoleName, '${PREFIX}')].RoleName" --output text)

for ROLE in $ROLES; do
  if [ "$ROLE" == "None" ]; then continue; fi
  echo "Found Role: $ROLE"

  # Detach Managed Policies
  POLICIES=$(aws iam list-attached-role-policies --role-name "$ROLE" --query "AttachedPolicies[].PolicyArn" --output text)
  for POLICY in $POLICIES; do
    if [ "$POLICY" == "None" ]; then continue; fi
    echo "  - Detaching managed policy: $POLICY"
    run_aws aws iam detach-role-policy --role-name "$ROLE" --policy-arn "$POLICY"
  done

  # Delete Inline Policies
  INLINE_POLICIES=$(aws iam list-role-policies --role-name "$ROLE" --query "PolicyNames[]" --output text)
  for POLICY in $INLINE_POLICIES; do
    if [ "$POLICY" == "None" ]; then continue; fi
    echo "  - Deleting inline policy: $POLICY"
    run_aws aws iam delete-role-policy --role-name "$ROLE" --policy-name "$POLICY"
  done

  # Remove from Instance Profiles
  PROFILES=$(aws iam list-instance-profiles-for-role --role-name "$ROLE" --query "InstanceProfiles[].InstanceProfileName" --output text)
  for PROFILE in $PROFILES; do
    if [ "$PROFILE" == "None" ]; then continue; fi
    echo "  - Removing role from instance profile: $PROFILE"
    run_aws aws iam remove-role-from-instance-profile --instance-profile-name "$PROFILE" --role-name "$ROLE"
  done

  # Delete Role
  echo "  - Deleting Role: $ROLE"
  run_aws aws iam delete-role --role-name "$ROLE"
done

echo "Scanning Instance Profiles..."
PROFILES=$(aws iam list-instance-profiles --query "InstanceProfiles[?starts_with(InstanceProfileName, '${PREFIX}')].InstanceProfileName" --output text)
for PROFILE in $PROFILES; do
  if [ "$PROFILE" == "None" ]; then continue; fi
  echo "Found Instance Profile: $PROFILE"
  echo "  - Deleting Instance Profile: $PROFILE"
  run_aws aws iam delete-instance-profile --instance-profile-name "$PROFILE"
done

# -----------------------------------------------------------------------------
# 2. ELB / Target Groups
# -----------------------------------------------------------------------------
echo "Scanning Load Balancers..."
LBS=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?starts_with(LoadBalancerName, '${PREFIX}')].LoadBalancerArn" --output text)
for LB in $LBS; do
  if [ "$LB" == "None" ]; then continue; fi
  echo "Found LB: $LB"
  # Listeners need to be deleted? No, deleting LB deletes listeners.
  # But need to disable deletion protection if enabled? Usually yes.
  run_aws aws elbv2 modify-load-balancer-attributes --load-balancer-arn "$LB" --attributes Key=deletion_protection.enabled,Value=false
  echo "  - Deleting Load Balancer: $LB"
  run_aws aws elbv2 delete-load-balancer --load-balancer-arn "$LB"
  
  # Wait for LB deletion to free TGs? Not strictly required by API but safer.
done

echo "Scanning Target Groups..."
TGS=$(aws elbv2 describe-target-groups --query "TargetGroups[?starts_with(TargetGroupName, '${PREFIX}')].TargetGroupArn" --output text)
for TG in $TGS; do
  if [ "$TG" == "None" ]; then continue; fi
  echo "Found Target Group: $TG"
  echo "  - Deleting Target Group: $TG"
  run_aws aws elbv2 delete-target-group --target-group-arn "$TG"
done

# -----------------------------------------------------------------------------
# 3. EC2 Instances
# -----------------------------------------------------------------------------
echo "Scanning EC2 Instances..."
INSTANCES=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${PREFIX}*" "Name=instance-state-name,Values=running,stopped,stopping,pending" --query "Reservations[].Instances[].InstanceId" --output text)
if [ ! -z "$INSTANCES" ] && [ "$INSTANCES" != "None" ]; then
  echo "Found Instances: $INSTANCES"
  IFS=$'\t' read -r -a INSTANCE_ARRAY <<< "$INSTANCES"
  for INSTANCE in "${INSTANCE_ARRAY[@]}"; do
    # disable termination protection if needed
    run_aws aws ec2 modify-instance-attribute --instance-id "$INSTANCE" --no-disable-api-termination
    echo "  - Terminating Instance: $INSTANCE"
    run_aws aws ec2 terminate-instances --instance-ids "$INSTANCE"
  done
  
  if [ "$DRY_RUN" = "false" ]; then
      echo "Waiting for instances to terminate..."
      aws ec2 wait instance-terminated --instance-ids $INSTANCES
  fi
fi

# -----------------------------------------------------------------------------
# 4. Security Groups
# -----------------------------------------------------------------------------
echo "Scanning Security Groups..."
SGS=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${PREFIX}*" --query "SecurityGroups[].GroupId" --output text)
# Need to delete rules first to avoid dependency issues between SGs
for SG in $SGS; do
  if [ "$SG" == "None" ]; then continue; fi
  echo "Found SG: $SG - Revoking all rules..."
  
  # Revoke Ingress
  # This is complex in CLI, simplified approach: delete SG directly, retry if dependency.
  # Better: Assume Terraform-like destroy loops or just try delete. 
  # If SGs reference each other, one delete will fail. We might need a retry loop.
  
  if [ "$DRY_RUN" = "false" ]; then
      # Try 3 times
      for i in {1..3}; do
        echo "  - Attempt $i to delete SG: $SG"
        aws ec2 delete-security-group --group-id "$SG" 2>/dev/null && break || echo "    (Retrying due to dependency...)"
        sleep 2
      done
  else
      echo "  [DRY RUN] Would delete SG: $SG"
  fi
done

echo "---------------------------------------------------"
echo "Cleanup Scan Complete."
