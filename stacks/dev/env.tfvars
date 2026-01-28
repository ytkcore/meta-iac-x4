region = "ap-northeast-2"

# Naming
env     = "dev"
name    = "dev-network"
project = "dev"

# Root Domain (공통)
# 예) "example.com"
# placeholder(example.com)일 경우 make apply 시 입력을 요청하고 env.auto.tfvars에 저장합니다.
base_domain = "example.com"

tags = {
  ManagedBy = "terraform"
  Project   = "dev"
  Env       = "dev"
}

# Remote state (S3 backend)
state_bucket     = "enc-tfstate"
state_region     = "ap-northeast-2"
state_key_prefix = "enc-iac"


# Multi-AZ (default: a,c)
azs = ["ap-northeast-2a", "ap-northeast-2c"]

# =============================================================================
# VPC Endpoints (20-endpoints)
# =============================================================================
# SSM 필수 엔드포인트: ssm, ssmmessages, ec2messages
# Harbor/RKE2 필수: ecr.api, ecr.dkr, s3 (Gateway는 00-network에서 생성)
enable_interface_endpoints = true
interface_services = [
  "ssm",
  "ssmmessages",
  "ec2messages",
  "ecr.api",
  "ecr.dkr",
  "logs"
]

# Harbor (Internal Registry / Cache)
# - VPC 내부망 디폴트: HTTP(80)
# - 필요 시 harbo r_enable_tls=true 로 HTTPS(443, self-signed) 활성화
harbor_hostname            = "harbor.internal"
harbor_enable_tls          = false
harbor_proxy_cache_project = "dockerhub-proxy"

# Databases
# postgres_mode: "self" (EC2) | "rds" (RDS instance) | "aurora" (Aurora PostgreSQL)
postgres_mode = "self"

# Self-managed images (Docker)
postgres_image_tag = "18.1"
neo4j_image_tag    = "5.26.19"

# Optional: override instance types for DB nodes (self-managed)
db_instance_type   = "t3.large"
db_root_volume_gib = 50

# Optional: pick a subnet tier (default: "db")
db_subnet_tier = "db"

# Optional: allow DB access from additional SGs (in addition to RKE2 nodes SG)
allow_additional_sg_ids = []

# Optional: if you haven't applied 50-rke2 yet, set to false (will allow from VPC CIDR only)
require_rke2_state = true

# Public Ingress NLB (Optional)
# - RKE2 Nginx Ingress Controller의 NodePort를 외부에 노출
# - 기본값: false (비활성화)
enable_public_ingress_nlb = true
ingress_http_nodeport     = 30080
ingress_https_nodeport    = 30443

# Managed Postgres options
rds_instance_class    = "db.t4g.micro"
aurora_instance_class = "db.t4g.medium"

# Database credentials
postgres_db_name     = "app"
postgres_db_username = "app"
# postgres_db_password = "ChangeMe123!" # optional (if omitted, Terraform generates one)
# neo4j_password       = "ChangeMe123!" # optional (if omitted, Terraform generates one)