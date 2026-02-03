provider "aws" {
  region = var.region
}

# ------------------------------------------------------------------------------
# Golden Image Lookup
# ------------------------------------------------------------------------------
data "aws_ami" "golden" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["meta-golden-image-al2023-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

locals {
  stack_network  = "00-network"
  stack_security = "10-security"
  stack_rke2     = "50-rke2"

  key_network  = "${var.state_key_prefix}/${var.env}/${local.stack_network}.tfstate"
  key_security = "${var.state_key_prefix}/${var.env}/${local.stack_security}.tfstate"

  common_tags = {
    ManagedBy   = "terraform"
    Project     = var.project
    Environment = var.env
  }
}

# ------------------------------------------------------------------------------
# Remote States
# ------------------------------------------------------------------------------
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.state_region
    key    = local.key_network
  }
}

data "terraform_remote_state" "harbor" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.state_region
    key    = "${var.state_key_prefix}/${var.env}/40-harbor.tfstate"
  }
}

data "terraform_remote_state" "security" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.state_region
    key    = local.key_security
  }
}

# ------------------------------------------------------------------------------
# Local Variables & Subnet Mapping
# ------------------------------------------------------------------------------
locals {
  vpc_id   = try(data.terraform_remote_state.network.outputs.vpc_id, "")
  vpc_cidr = try(data.terraform_remote_state.network.outputs.vpc_cidr, "")

  # Subnets categorized by Tier and AZ
  # network 스택의 Outputs 예상 구조: subnet_ids = { "db-pri-a": "id...", "db-pri-c": "id..." }
  all_subnet_ids = try(data.terraform_remote_state.network.outputs.subnet_ids, {})

  # AZ-a: PostgreSQL / AZ-c: Neo4j
  postgres_subnet_id = try(local.all_subnet_ids["db-pri-a"], "")
  neo4j_subnet_id    = try(local.all_subnet_ids["db-pri-c"], "")

  harbor_registry_hostport = try(data.terraform_remote_state.harbor.outputs.harbor_registry_hostport, "")
  harbor_scheme            = try(data.terraform_remote_state.harbor.outputs.harbor_scheme, "https")
  harbor_project           = try(data.terraform_remote_state.harbor.outputs.harbor_proxy_cache_project, "library")

  # Logical Identity SGs (Static identity from 10-security)
  k8s_client_sg_id = try(data.terraform_remote_state.security.outputs.k8s_client_sg_id, "")
  ops_client_sg_id = try(data.terraform_remote_state.security.outputs.ops_client_sg_id, "")

  # K8s Node Subnet CIDRs (Logical location from 00-network)
  # tier 별로 CIDRs를 합산하여 리스트를 만듭니다.
  k8s_subnet_cidrs = try(data.terraform_remote_state.network.outputs.subnet_cidrs_by_tier["k8s_dp"], [])

  allowed_cidrs = distinct(concat([local.vpc_cidr], local.k8s_subnet_cidrs))
  allowed_sgs   = compact([local.k8s_client_sg_id, local.ops_client_sg_id])

  # [NEW] Private DNS Integration
  route53_zone_id = try(data.terraform_remote_state.network.outputs.route53_zone_id, "")
  base_domain     = try(data.terraform_remote_state.network.outputs.base_domain, var.base_domain)
}

# ------------------------------------------------------------------------------
# Credentials
# ------------------------------------------------------------------------------
resource "random_password" "postgres" {
  length  = 24
  special = true
}

resource "random_password" "neo4j" {
  length  = 24
  special = true
}

locals {
  postgres_password_effective = coalesce(var.postgres_password, random_password.postgres.result)
  neo4j_password_effective    = coalesce(var.neo4j_password, random_password.neo4j.result)
}

# ------------------------------------------------------------------------------
# Standalone DB Instances (Consolidated)
# ------------------------------------------------------------------------------

# 1. PostgreSQL (AZ-a)
module "postgres" {
  source = "../../../modules/postgres-standalone"

  name    = "postgres"
  env     = var.env
  project = var.project

  vpc_id    = local.vpc_id
  subnet_id = local.postgres_subnet_id

  instance_type       = var.db_instance_type
  root_volume_size_gb = var.db_root_volume_gb

  postgres_image_tag = var.postgres_image_tag
  db_name            = var.postgres_db_name
  db_username        = var.postgres_username
  db_password        = local.postgres_password_effective

  allowed_sg_ids      = local.allowed_sgs
  allowed_cidr_blocks = local.allowed_cidrs

  tags = merge(local.common_tags, { Role = "postgres" })

  # Use the custom Golden Image (AL2023 with Docker/SSM)
  ami_id                   = data.aws_ami.golden.id
  harbor_registry_hostport = local.harbor_registry_hostport
  harbor_scheme            = local.harbor_scheme
  harbor_project           = local.harbor_project
  harbor_insecure          = true
}

# 2. Neo4j (AZ-c)
module "neo4j" {
  source = "../../../modules/neo4j-standalone"

  name    = "neo4j"
  env     = var.env
  project = var.project

  vpc_id    = local.vpc_id
  subnet_id = local.neo4j_subnet_id

  instance_type       = var.db_instance_type
  root_volume_size_gb = var.db_root_volume_gb

  neo4j_image_tag = var.neo4j_image_tag
  neo4j_password  = local.neo4j_password_effective

  allowed_sg_ids      = local.allowed_sgs
  allowed_cidr_blocks = local.allowed_cidrs

  tags = merge(local.common_tags, { Role = "neo4j" })

  # Use the custom Golden Image (AL2023 with Docker/SSM)
  ami_id                   = data.aws_ami.golden.id
  harbor_registry_hostport = local.harbor_registry_hostport
  harbor_project           = local.harbor_project
  harbor_insecure          = true
}

# ------------------------------------------------------------------------------
# 3. Private DNS Records (Optional)
# ------------------------------------------------------------------------------
resource "aws_route53_record" "postgres" {
  count   = local.route53_zone_id != "" ? 1 : 0
  zone_id = local.route53_zone_id
  name    = "postgres.${var.env}.${var.project}"
  type    = "A"
  ttl     = 300
  records = [module.postgres.private_ip]
}

resource "aws_route53_record" "neo4j" {
  count   = local.route53_zone_id != "" ? 1 : 0
  zone_id = local.route53_zone_id
  name    = "neo4j.${var.env}.${var.project}"
  type    = "A"
  ttl     = 300
  records = [module.neo4j.private_ip]
}
