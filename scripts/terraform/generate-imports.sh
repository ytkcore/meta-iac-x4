#!/bin/bash
# =============================================================================
# Generate Imports - Native Terraform 1.5+ Transition Helper
# =============================================================================
set -e

STACK=$1
ENV=${ENV:-dev}
PROJECT=${PROJECT:-meta}

if [[ -z "$STACK" ]]; then
    echo "Usage: $0 <stack-name>"
    exit 1
fi

TARGET_FILE="stacks/${ENV}/${STACK}/imports.tf"
if [[ ! -f "$TARGET_FILE" ]]; then
    echo "❌ Error: $TARGET_FILE not found."
    exit 1
fi

log() { echo -e "\033[32m[GEN-IMPORT] $1\033[0m" >&2; }

# Common Prefixes
BASE_NAME="${ENV}-${PROJECT}"
NETWORK_BASE="${ENV}-${PROJECT}-network"

# Find Helper
find_id() {
    local TYPE=$1
    local TAG_NAME=$2
    local QUERY=$3
    log "Finding $TYPE for $TAG_NAME..."
    local ID=$(aws ec2 $TYPE --filters "Name=tag:Name,Values=$TAG_NAME" --query "$QUERY" --output text 2>/dev/null || echo "None")
    echo "$ID"
}

# Process imports.tf
TEMP_FILE="${TARGET_FILE}.tmp"
cp "$TARGET_FILE" "$TEMP_FILE"

# 1. Uncomment active import blocks
# (We assume the templates are commented with /* ... */)
# This is a bit complex for sed, let's just do a simple line-by-line replacement if needed.
# Or just strip the comment markers.
sed -i '' 's/\/\*//g' "$TEMP_FILE"
sed -i '' 's/\*\///g' "$TEMP_FILE"

# 2. Replace placeholders (Specific to each stack)
case "$STACK" in
    "00-network")
        VPC_ID=$(find_id "describe-vpcs" "${NETWORK_BASE}-vpc" "Vpcs[0].VpcId")
        sed -i '' "s|VPC_ID|$VPC_ID|" "$TEMP_FILE"
        
        IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=${NETWORK_BASE}-igw" --query "InternetGateways[0].InternetGatewayId" --output text)
        sed -i '' "s|IGW_ID|$IGW_ID|" "$TEMP_FILE"

        # Subnets (Map logic)
        for KEY in common-pub-a common-pub-c db-pri-a db-pri-c k8s-cp-pri-a k8s-cp-pri-c k8s-dp-pri-a k8s-dp-pri-c common-pri-a common-pri-c; do
            ID=$(find_id "describe-subnets" "${NETWORK_BASE}-snet-${KEY}" "Subnets[0].SubnetId")
            sed -i '' "/module.network.aws_subnet.this\[\"$KEY\"\]/,/id =/ s|SUBNET_ID|$ID|" "$TEMP_FILE"
        done

        # NAT Gws
        for AZ in ap-northeast-2a ap-northeast-2c; do
            ID=$(aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=${NETWORK_BASE}-nat-${AZ}" --query "NatGateways[0].NatGatewayId" --output text)
            sed -i '' "/module.network.aws_nat_gateway.this\[\"$AZ\"\]/,/id =/ s|NAT_GW_ID|$ID|" "$TEMP_FILE"
        done

        # Route Tables
        ID_PUB=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=${NETWORK_BASE}-rt-public" --query "RouteTables[0].RouteTableId" --output text)
        sed -i '' "/aws_route_table.public/,/id =/ s|RT_ID|$ID_PUB|" "$TEMP_FILE"
        
        for AZ in ap-northeast-2a ap-northeast-2c; do
            ID_PRI=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=${NETWORK_BASE}-rt-private-${AZ}" --query "RouteTables[0].RouteTableId" --output text)
            sed -i '' "/aws_route_table.private\[\"$AZ\"\]/,/id =/ s|RT_ID|$ID_PRI|" "$TEMP_FILE"
            
            ID_DB=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=${NETWORK_BASE}-rt-db-${AZ}" --query "RouteTables[0].RouteTableId" --output text)
            sed -i '' "/aws_route_table.db\[\"$AZ\"\]/,/id =/ s|RT_ID|$ID_DB|" "$TEMP_FILE"
        done
        ;;

    "05-security")
        SG_BASE="${ENV}-${PROJECT}-security"
        KEYS="bastion breakglass-ssh lb-public k8s-cp k8s-worker db vpce k8s-client ops-client monitoring-client"
        for KEY in $KEYS; do
            TF_KEY=${KEY//-/_}
            SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${SG_BASE}-${KEY}" --query "SecurityGroups[0].GroupId" --output text)
            sed -i '' "/aws_security_group.$TF_KEY/,/id =/ s|SG_ID|$SG_ID|" "$TEMP_FILE"
        done
        ;;

    "30-bastion")
        BASTION_BASE="${ENV}-${PROJECT}-bastion"
        SG_ID=$(find_id "describe-security-groups" "${BASTION_BASE}-sg" "SecurityGroups[0].GroupId")
        sed -i '' "/aws_security_group.bastion/,/id =/ s|SG_ID|$SG_ID|" "$TEMP_FILE"
        
        # Try wildcard match for instances
        INST_ID=$(find_id "describe-instances" "${BASTION_BASE}*" "Reservations[0].Instances[0].InstanceId")
        sed -i '' "/module.bastion.aws_instance.this/,/id =/ s|INSTANCE_ID|$INST_ID|" "$TEMP_FILE"

        # Fix role name
        ROLE_NAME="${BASTION_BASE}-role"
        sed -i '' "s|bastion-role|$ROLE_NAME|g" "$TEMP_FILE"
        ;;

    "40-harbor")
        HARBOR_BASE="${ENV}-${PROJECT}-harbor"
        # Try wildcard match for instances
        INST_ID=$(find_id "describe-instances" "${HARBOR_BASE}*" "Reservations[0].Instances[0].InstanceId")
        sed -i '' "/module.harbor.module.ec2.aws_instance.this/,/id =/ s|INSTANCE_ID|$INST_ID|" "$TEMP_FILE"
        
        ALB_ARN=$(aws elbv2 describe-load-balancers --names "${HARBOR_BASE}-alb" --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null || echo "None")
        sed -i '' "/aws_lb.harbor/,/id =/ s|ALB_ARN|$ALB_ARN|" "$TEMP_FILE"
        
        S3_NAME=$(aws s3api list-buckets --query "Buckets[?contains(Name, '${HARBOR_BASE}-storage')].Name" --output text)
        sed -i '' "/aws_s3_bucket.created/,/id =/ s|BUCKET_NAME|$S3_NAME|" "$TEMP_FILE"
        ;;

    "50-rke2")
        RKE2_BASE="${ENV}-${PROJECT}-k8s"
        ROLE_NAME="${ENV}-${PROJECT}-rke2-node-role"
        sed -i '' "s|ROLE_NAME|$ROLE_NAME|g" "$TEMP_FILE"
        sed -i '' "s|PROFILE_NAME|$ROLE_NAME|g" "$TEMP_FILE"
        
        POLICY_ARN=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='${ENV}-${PROJECT}-external-dns-policy'].Arn" --output text)
        sed -i '' "s|POLICY_ARN|$POLICY_ARN|g" "$TEMP_FILE"
        
        SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${RKE2_BASE}-nodes-sg" --query "SecurityGroups[0].GroupId" --output text)
        sed -i '' "/aws_security_group.nodes/,/id =/ s|SG_ID|$SG_ID|" "$TEMP_FILE"
        
        for KEY in cp-01 cp-02 cp-03 worker-01 worker-02 worker-03 worker-04; do
            INST_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${RKE2_BASE}-${KEY}" "Name=instance-state-name,Values=running,pending,stopped" --query "Reservations[0].Instances[0].InstanceId" --output text)
            sed -i '' "/aws_instance.*\[\"$KEY\"\]/,/id =/ s|INSTANCE_ID|$INST_ID|" "$TEMP_FILE"
        done
        ;;

    "60-db")
        PG_BASE="${ENV}-${PROJECT}-postgres"
        PG_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${PG_BASE}-sg" --query "SecurityGroups[0].GroupId" --output text)
        PG_INST=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${PG_BASE}" "Name=instance-state-name,Values=running,pending,stopped" --query "Reservations[0].Instances[0].InstanceId" --output text)
        sed -i '' "/module.postgres.aws_security_group.this/,/id =/ s|SG_ID|$PG_SG|" "$TEMP_FILE"
        sed -i '' "/module.postgres.module.instance.aws_instance.this/,/id =/ s|INSTANCE_ID|$PG_INST|" "$TEMP_FILE"

        NEO_BASE="${ENV}-${PROJECT}-neo4j"
        NEO_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${NEO_BASE}-sg" --query "SecurityGroups[0].GroupId" --output text)
        NEO_INST=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${NEO_BASE}" "Name=instance-state-name,Values=running,pending,stopped" --query "Reservations[0].Instances[0].InstanceId" --output text)
        sed -i '' "/module.neo4j.aws_security_group.this/,/id =/ s|SG_ID|$NEO_SG|" "$TEMP_FILE"
        sed -i '' "/module.neo4j.module.instance.aws_instance.this/,/id =/ s|INSTANCE_ID|$NEO_INST|" "$TEMP_FILE"

        # Route53 (DB records)
        BASE_DOMAIN=$(grep '^base_domain' "stacks/${ENV}/env.tfvars" | cut -d'=' -f2 | tr -d ' "' || echo "meta.internal")
        ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='${BASE_DOMAIN}.'].Id" --output text | cut -d'/' -f3)

        if [[ -n "$ZONE_ID" && "$ZONE_ID" != "None" ]]; then
            sed -i '' "s|ZONE_ID|$ZONE_ID|g" "$TEMP_FILE"
        fi
        ;;

    "70-observability")
        S3_NAME=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'longhorn-backup')].Name" --output text)
        sed -i '' "/aws_s3_bucket.longhorn_backup/,/id =/ s|BUCKET_NAME|$S3_NAME|" "$TEMP_FILE"
        ;;
esac

mv "$TEMP_FILE" "$TARGET_FILE"
log "✅ Successfully generated imports.tf for $STACK"
