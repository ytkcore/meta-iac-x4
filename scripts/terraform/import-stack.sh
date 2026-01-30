#!/bin/bash
set -e

STACK_NAME=$1
TF_VAR_OPTS_FROM_MAKE=$2
PROJECT="meta"
# Default to 'dev' if ENV not set
ENV="${ENV:-dev}"
TF_VARS_FILE="stacks/${ENV}/env.tfvars"
PROJECT="meta"
AWS_REGION="ap-northeast-2"

# Try to read ENV and PROJECT from env.tfvars for consistency
if [[ -f "$TF_VARS_FILE" ]]; then
    # Read values, handling potential whitespace and double quotes
    FILE_ENV=$(grep '^env[[:space:]]*=' "$TF_VARS_FILE" | cut -d'=' -f2 | tr -d ' "')
    FILE_PROJECT=$(grep '^project[[:space:]]*=' "$TF_VARS_FILE" | cut -d'=' -f2 | tr -d ' "')
    
    if [[ -n "$FILE_ENV" ]]; then ENV="$FILE_ENV"; fi
    if [[ -n "$FILE_PROJECT" ]]; then PROJECT="$FILE_PROJECT"; fi
fi

# Note: we are currently in the project root, but will CD to stack dir
# After CDing to stacks/${ENV}/00-network, the vars are at ../env.tfvars

log() { echo -e "\033[32m[IMPORT-${STACK_NAME}] $1\033[0m"; }
error() { echo -e "\033[31m[ERROR] $1\033[0m"; exit 1; }
check_resource() {
    # $1: Terraform Resource Address
    # $2: AWS ID
    
    local TF_VAR_OPTS=""
    if [[ -n "$TF_VAR_OPTS_FROM_MAKE" ]]; then
        TF_VAR_OPTS="$TF_VAR_OPTS_FROM_MAKE"
    else
        # Fallback to local detection if not passed from Makefile
        if [[ -f "../env.tfvars" ]]; then
            TF_VAR_OPTS="-var-file=../env.tfvars"
        fi
        if [[ -f "../env.auto.tfvars" ]]; then
            TF_VAR_OPTS="$TF_VAR_OPTS -var-file=../env.auto.tfvars"
        fi
    fi

    if terraform state show "$1" >/dev/null 2>&1; then
        log "Resource $1 is already managed."
    else
        log "Importing $1 with ID $2..."
        terraform import $TF_VAR_OPTS "$1" "$2"
    fi
}

try_import() {
    # $1: Terraform Resource Address
    # $2: AWS ID / Resource ID
    
    local TF_VAR_OPTS=""
    if [[ -n "$TF_VAR_OPTS_FROM_MAKE" ]]; then
        TF_VAR_OPTS="$TF_VAR_OPTS_FROM_MAKE"
    else
        # Fallback to local detection if not passed from Makefile
        if [[ -f "../env.tfvars" ]]; then
            TF_VAR_OPTS="-var-file=../env.tfvars"
        fi
        if [[ -f "../env.auto.tfvars" ]]; then
            TF_VAR_OPTS="$TF_VAR_OPTS -var-file=../env.auto.tfvars"
        fi
    fi

    if terraform state show "$1" >/dev/null 2>&1; then
        log "Resource $1 is already managed."
    else
        log "Attempting import of $1 with ID $2..."
        # Use simple if/else to catch failure without set -e exit
        if terraform import $TF_VAR_OPTS "$1" "$2"; then
             log "Import successful."
        else
             log "Import failed (resource likely not found). Will be created by plan."
        fi
    fi
}

import_00_network() {
    BASE_NAME="${ENV}-${PROJECT}-network"
    
    # 1. VPC
    # Name Tag: dev-meta-network-vpc (based on main.tf: ${local.base_name}-vpc)
    # Wait, in main.tf base_name = "${var.env}-${var.project}-${local.workload}" -> "dev-dev-network"? 
    # Ah, variables.tf says project="meta" usually. User entered "meta" in init.
    # So base_name = "dev-meta-network"
    
    # Let's verify project name from env.tfvars if possible, or assume 'meta' from user input
    PROJECT_NAME="meta" 
    BASE_NAME="${ENV}-${PROJECT_NAME}-network"

    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${BASE_NAME}-vpc" --query "Vpcs[0].VpcId" --output text)
    if [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]]; then
        error "VPC with tag Name=${BASE_NAME}-vpc not found."
    fi
    check_resource "module.vpc.aws_vpc.this" "$VPC_ID"

    # 2. IGW
    IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=${VPC_ID}" --query "InternetGateways[0].InternetGatewayId" --output text)
    if [[ "$IGW_ID" != "None" ]]; then
        check_resource "module.igw.aws_internet_gateway.this" "$IGW_ID"
    fi

    SUBNET_KEYS="pub-a pub-c k8s-cp-pri-a k8s-cp-pri-c k8s-dp-pri-a k8s-dp-pri-c common-pri-a common-pri-c db-pri-a db-pri-c"
    
    for KEY in $SUBNET_KEYS; do
        TAG_NAME="${BASE_NAME}-subnet-${KEY}"
        log "Searching for subnet with Name: ${TAG_NAME}"
        
        SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=${TAG_NAME}" --query "Subnets[0].SubnetId" --output text)
        
        # If not found (None or empty), try flexible search as fallback
        if [[ "$SUBNET_ID" == "None" || -z "$SUBNET_ID" ]]; then
             log "Not found with exact match, trying flexible search (*${KEY}*)..."
             SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=*${KEY}*" --query "Subnets[0].SubnetId" --output text)
        fi
        
        if [[ "$SUBNET_ID" != "None" && -n "$SUBNET_ID" ]]; then
            check_resource "module.subnets.aws_subnet.this[\"${KEY}\"]" "$SUBNET_ID"
        else
            log "Warning: Subnet for key ${KEY} (Tag: ${TAG_NAME}) not found in AWS."
        fi
    done

    # 4. NAT Gateways
    # Keys: ap-northeast-2a, ap-northeast-2c
    NATS=("ap-northeast-2a" "ap-northeast-2c")
    for AZ in "${NATS[@]}"; do
        NAT_ID=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=${BASE_NAME}-nat-${AZ}" --query "NatGateways[0].NatGatewayId" --output text)
         if [[ "$NAT_ID" != "None" && -n "$NAT_ID" ]]; then
            check_resource "module.nat.aws_nat_gateway.this[\"${AZ}\"]" "$NAT_ID"
        fi
    done
    
    # 5. Route Tables
    # Public
    RT_PUB=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=${BASE_NAME}-rt-public" --query "RouteTables[0].RouteTableId" --output text)
    if [[ "$RT_PUB" != "None" ]]; then
        check_resource "module.routing.aws_route_table.public" "$RT_PUB"
    fi
    
    # Private & DB (by AZ)
    # module.routing.aws_route_table.private["ap-northeast-2a"]
    for AZ in "${NATS[@]}"; do
        RT_PRI=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=${BASE_NAME}-rt-private-${AZ}" --query "RouteTables[0].RouteTableId" --output text)
        if [[ "$RT_PRI" != "None" && -n "$RT_PRI" ]]; then
             check_resource "module.routing.aws_route_table.private[\"${AZ}\"]" "$RT_PRI"
        fi
        
        RT_DB=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=${BASE_NAME}-rt-db-${AZ}" --query "RouteTables[0].RouteTableId" --output text)
         if [[ "$RT_DB" != "None" && -n "$RT_DB" ]]; then
             check_resource "module.routing.aws_route_table.db[\"${AZ}\"]" "$RT_DB"
        fi
    done
}

import_10_security() {
    BASE_NAME_SG="${ENV}-${PROJECT}"
    SG_NAMES=("bastion" "breakglass-ssh" "lb-public" "k8s-cp" "k8s-worker" "db" "vpce")
    
    for SG_SUFFIX in "${SG_NAMES[@]}"; do
        SG_NAME="${BASE_NAME_SG}-${SG_SUFFIX}"
        SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" --query "SecurityGroups[0].GroupId" --output text)
        if [[ "$SG_ID" != "None" && -n "$SG_ID" ]]; then
            check_resource "module.security_groups.aws_security_group.${SG_SUFFIX/-/_}" "$SG_ID"
        fi
    done
}

import_20_endpoints() {
    BASE_NAME_VPCE="${ENV}-${PROJECT}"
    
    # Optional SG
    SG_ID=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=${BASE_NAME_VPCE}-vpce-*" --query "SecurityGroups[0].GroupId" --output text)
    if [[ "$SG_ID" != "None" && -n "$SG_ID" ]]; then
        check_resource "aws_security_group.vpce[0]" "$SG_ID"
    fi

    # Interface Endpoints
    SERVICES=("ec2" "ssm" "ssmmessages" "ec2messages" "logs")
    for SVC in "${SERVICES[@]}"; do
        VPCE_ID=$(aws ec2 describe-vpc-endpoints --filters "Name=tag:Service,Values=$SVC" --query "VpcEndpoints[0].VpcEndpointId" --output text)
        if [[ "$VPCE_ID" != "None" && -n "$VPCE_ID" ]]; then
            check_resource "module.endpoints.aws_vpc_endpoint.interface[\"$SVC\"]" "$VPCE_ID"
        fi
    done
}

import_30_db() {
    SNG_NAME="${ENV}-${PROJECT}-db-subnet-group"
    check_resource "module.db_subnet_group.aws_db_subnet_group.this" "$SNG_NAME"
}

import_40_bastion() {
    BASE_NAME_BASTION="${ENV}-${PROJECT}-bastion"
    
    # Security Group
    SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${BASE_NAME_BASTION}-sg" --query "SecurityGroups[0].GroupId" --output text)
    if [[ "$SG_ID" != "None" && -n "$SG_ID" ]]; then
        check_resource "aws_security_group.bastion[0]" "$SG_ID"
    fi

    # EC2 Instance
    INST_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${BASE_NAME_BASTION}" "Name=instance-state-name,Values=running,pending,stopped" --query "Reservations[0].Instances[0].InstanceId" --output text)
    if [[ "$INST_ID" != "None" && -n "$INST_ID" ]]; then
        check_resource "module.bastion.aws_instance.this" "$INST_ID"
    fi
}

import_45_harbor() {
    BASE_NAME_HARBOR="${ENV}-${PROJECT}-harbor"
    
    # EC2 Instance
    INST_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${BASE_NAME_HARBOR}" "Name=instance-state-name,Values=running,pending,stopped" --query "Reservations[0].Instances[0].InstanceId" --output text)
    if [[ "$INST_ID" != "None" && -n "$INST_ID" ]]; then
        # Harbor module uses 'ec2' submodule
        check_resource "module.harbor.module.ec2.aws_instance.this" "$INST_ID"
    fi

    # ALB
    ALB_ARN=$(aws elbv2 describe-load-balancers --names "${BASE_NAME_HARBOR}-alb" --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null || echo "None")
    if [[ "$ALB_ARN" != "None" ]]; then
        check_resource "module.harbor.aws_lb.harbor[0]" "$ALB_ARN"
    fi

    # S3
    S3_NAME=$(aws s3api list-buckets --query "Buckets[?contains(Name, '${BASE_NAME_HARBOR}-storage')].Name" --output text)
    if [[ -n "$S3_NAME" ]]; then
        check_resource "module.harbor.aws_s3_bucket.created[0]" "$S3_NAME"
    fi
}

import_50_rke2() {
    BASE_NAME_K8S="${ENV}-${PROJECT}-k8s"
    
    # 1. IAM Role & Instance Profile
    check_resource "module.rke2.aws_iam_role.nodes" "${BASE_NAME_K8S}-role"
    check_resource "module.rke2.aws_iam_instance_profile.nodes" "${BASE_NAME_K8S}-profile"

    # 2. Security Group
    SG_ID=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=${BASE_NAME_K8S}-common-sg" --query "SecurityGroups[0].GroupId" --output text)
    if [[ "$SG_ID" != "None" && -n "$SG_ID" ]]; then
        check_resource "module.rke2.aws_security_group.nodes" "$SG_ID"
    fi

    # 3. Load Balancers (Internal NLB)
    LB_ARN=$(aws elbv2 describe-load-balancers --names "${BASE_NAME_K8S}-nlb-server" --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null || echo "None")
    if [[ "$LB_ARN" != "None" ]]; then
        check_resource "module.rke2.aws_lb.rke2[0]" "$LB_ARN"
        
        # Target Groups
        TG_SUP=$(aws elbv2 describe-target-groups --load-balancer-arn "$LB_ARN" --query "TargetGroups[?Port==\`9345\`].TargetGroupArn" --output text)
        if [[ -n "$TG_SUP" ]]; then check_resource "module.rke2.aws_lb_target_group.supervisor[0]" "$TG_SUP"; fi
        
        TG_API=$(aws elbv2 describe-target-groups --load-balancer-arn "$LB_ARN" --query "TargetGroups[?Port==\`6443\`].TargetGroupArn" --output text)
        if [[ -n "$TG_API" ]]; then check_resource "module.rke2.aws_lb_target_group.apiserver[0]" "$TG_API"; fi
    fi

    # 4. EC2 Instances
    # Control Planes (cp-01, cp-02, cp-03)
    for i in {01..03}; do
        INST_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${BASE_NAME_K8S}-cp-${i}" "Name=instance-state-name,Values=running,pending,stopped" --query "Reservations[0].Instances[0].InstanceId" --output text)
        if [[ "$INST_ID" != "None" && -n "$INST_ID" ]]; then
            check_resource "module.rke2.aws_instance.control_plane[\"cp-${i}\"]" "$INST_ID"
        fi
    done

    # Workers (worker-01, worker-02, worker-03, worker-04)
    for i in {01..04}; do
        INST_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${BASE_NAME_K8S}-worker-${i}" "Name=instance-state-name,Values=running,pending,stopped" --query "Reservations[0].Instances[0].InstanceId" --output text)
        if [[ "$INST_ID" != "None" && -n "$INST_ID" ]]; then
            check_resource "module.rke2.aws_instance.worker[\"worker-${i}\"]" "$INST_ID"
        fi
    done
}

import_55_bootstrap() {
    # 1. Helm Release (ArgoCD)
    # ID: <namespace>/<name>
    # Helm resources might not exist yet, so we try import but allow failure (to create)
    try_import "helm_release.argocd" "argocd/argocd"

    # 2. Kubernetes Secret (GitOps Repo Creds)
    # ID: <namespace>/<name>
    try_import "kubernetes_secret.argocd_repo_creds[0]" "argocd/repo-creds"

    # 3. Route53 Records
    # Need to find Zone ID first
    BASE_DOMAIN=$(grep 'base_domain' ../env.tfvars | cut -d'"' -f2 || echo "")
    if [[ -n "$BASE_DOMAIN" ]]; then
        ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "${BASE_DOMAIN}." --query "HostedZones[0].Id" --output text | cut -d'/' -f3)
        if [[ -n "$ZONE_ID" && "$ZONE_ID" != "None" ]]; then
             check_resource "aws_route53_record.argocd[0]" "${ZONE_ID}_argocd.${BASE_DOMAIN}_A"
             check_resource "aws_route53_record.rancher[0]" "${ZONE_ID}_rancher.${BASE_DOMAIN}_A"
        fi
    fi
}

import_55_rancher() {
    try_import "helm_release.cert_manager[0]" "cert-manager/cert-manager"
    try_import "helm_release.rancher" "cattle-system/rancher"
}

import_60_db() {
    # EC2 Modes
    PG_ID=$(aws ec2 describe-instances --filters "Name=tag:Role,Values=postgres" "Name=tag:Project,Values=$PROJECT" --query "Reservations[0].Instances[0].InstanceId" --output text 2>/dev/null || echo "None")
    if [[ "$PG_ID" != "None" && -n "$PG_ID" ]]; then
        check_resource "module.postgres[0].aws_instance.this" "$PG_ID"
    fi

    NEO_ID=$(aws ec2 describe-instances --filters "Name=tag:Role,Values=neo4j" "Name=tag:Project,Values=$PROJECT" --query "Reservations[0].Instances[0].InstanceId" --output text 2>/dev/null || echo "None")
    if [[ "$NEO_ID" != "None" && -n "$NEO_ID" ]]; then
        check_resource "module.neo4j.aws_instance.this" "$NEO_ID"
    fi

    # Managed Modes (RDS/Aurora)
    RDS_ID=$(aws rds describe-db-instances --db-instance-identifier "${ENV}-${PROJECT}-postgres-rds" --query "DBInstances[0].DBInstanceIdentifier" --output text 2>/dev/null || echo "None")
    if [[ "$RDS_ID" != "None" && -n "$RDS_ID" ]]; then
        check_resource "aws_db_instance.postgres[0]" "$RDS_ID"
    fi
}

if [[ -z "$STACK_NAME" ]]; then
    error "Usage: $0 <stack-name> (e.g. 00-network)"
fi

log "Starting import process for stack: $STACK_NAME"

log "Changing directory to stacks/${ENV}/${STACK_NAME}..."
cd "stacks/${ENV}/${STACK_NAME}"

echo "================================================================================"
echo " [Importing Resources] Stack: ${STACK_NAME}"
echo "================================================================================"

case "$STACK_NAME" in
    "00-network")
        import_00_network
        ;;
    "10-security")
        import_10_security
        ;;
    "20-endpoints")
        import_20_endpoints
        ;;
    "30-db")
        import_30_db
        ;;
    "40-bastion")
        import_40_bastion
        ;;
    "45-harbor")
        import_45_harbor
        ;;
    "50-rke2")
        import_50_rke2
        ;;
    "55-bootstrap")
        import_55_bootstrap
        ;;
    "55-rancher")
        import_55_rancher
        ;;
    "60-db")
        import_60_db
        ;;
    *)
        error "Unknown or unimplemented stack: $STACK_NAME"
        ;;
esac

log "Import completed for $STACK_NAME."
