provider "aws" {
  region = var.region
}

# DB subnet은 outbound=0 이므로 패키지 설치를 피하기 위해 docker 포함 AMI를 사용합니다.
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}


locals {
  stack_network  = "00-network"
  stack_security = "10-security"
  stack_rke2     = "50-rke2"

  key_network  = "${var.state_key_prefix}/${var.env}/${local.stack_network}.tfstate"
  key_security = "${var.state_key_prefix}/${var.env}/${local.stack_security}.tfstate"
  key_rke2     = "${var.state_key_prefix}/${var.env}/${local.stack_rke2}.tfstate"

  # Name Prefix for Managed DBs
  managed_db_prefix = "${var.env}-${var.project}-postgres"

  # [NEW] Generate tags locally
  common_tags = {
    ManagedBy   = "terraform"
    Project     = var.project
    Environment = var.env
  }
}

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
    key    = "${var.state_key_prefix}/${var.env}/45-harbor.tfstate"
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

data "terraform_remote_state" "rke2" {
  count   = var.require_rke2_state ? 1 : 0
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.state_region
    key    = local.key_rke2
  }
}

locals {
  vpc_id   = data.terraform_remote_state.network.outputs.vpc_id
  vpc_cidr = data.terraform_remote_state.network.outputs.vpc_cidr

  subnet_ids_by_tier = data.terraform_remote_state.network.outputs.subnet_ids_by_tier

  harbor_registry_hostport = data.terraform_remote_state.harbor.outputs.harbor_registry_hostport
  harbor_scheme            = data.terraform_remote_state.harbor.outputs.harbor_scheme
  harbor_project           = data.terraform_remote_state.harbor.outputs.harbor_proxy_cache_project
  db_subnet_ids            = try(local.subnet_ids_by_tier[var.db_subnet_tier], [])

  postgres_subnet_id = try(local.db_subnet_ids[0], null)
  neo4j_subnet_id    = try(local.db_subnet_ids[1], local.postgres_subnet_id)

  rke2_nodes_sg_id = var.require_rke2_state ? try(data.terraform_remote_state.rke2[0].outputs.nodes_security_group_id, null) : null

  # Always allow from VPC CIDR. Additionally, allow from RKE2 nodes SG when available.
  allowed_cidrs = [local.vpc_cidr]
  allowed_sgs   = compact([local.rke2_nodes_sg_id])
}

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

# Standalone PostgreSQL on EC2 (default)
module "postgres" {
  count  = var.postgres_mode == "self" ? 1 : 0
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

  ami_id                   = data.aws_ssm_parameter.ecs_ami.value
  harbor_registry_hostport = local.harbor_registry_hostport
  harbor_scheme            = local.harbor_scheme
  harbor_project           = local.harbor_project
  harbor_insecure          = true
}

# Standalone Neo4j on EC2
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

  ami_id                   = data.aws_ssm_parameter.ecs_ami.value
  harbor_registry_hostport = local.harbor_registry_hostport
  harbor_scheme            = local.harbor_scheme
  harbor_project           = local.harbor_project
  harbor_insecure          = true
}

# Managed PostgreSQL (optional): RDS
resource "aws_db_subnet_group" "postgres" {
  count = var.postgres_mode == "rds" || var.postgres_mode == "aurora" ? 1 : 0

  name       = "${local.managed_db_prefix}-subnet-group"
  subnet_ids = local.db_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.managed_db_prefix}-subnet-group"
  })
}

resource "aws_security_group" "postgres_managed" {
  count       = var.postgres_mode == "rds" || var.postgres_mode == "aurora" ? 1 : 0
  name        = "${local.managed_db_prefix}-managed-sg"
  description = "Managed PostgreSQL SG"
  vpc_id      = local.vpc_id

  dynamic "ingress" {
    for_each = length(local.allowed_sgs) > 0 ? ["sg"] : []
    content {
      description     = "PostgreSQL from RKE2 nodes"
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = local.allowed_sgs
    }
  }

  ingress {
    description = "PostgreSQL from VPC CIDR"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = local.allowed_cidrs
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.managed_db_prefix}-managed-sg"
  })
}

resource "aws_db_instance" "postgres" {
  count = var.postgres_mode == "rds" ? 1 : 0

  identifier = "${local.managed_db_prefix}-rds"

  engine         = "postgres"
  engine_version = var.rds_engine_version
  instance_class = var.rds_instance_class

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  username = var.postgres_username
  password = local.postgres_password_effective
  db_name  = var.postgres_db_name

  db_subnet_group_name   = aws_db_subnet_group.postgres[0].name
  vpc_security_group_ids = [aws_security_group.postgres_managed[0].id]

  publicly_accessible = false

  backup_retention_period = var.backup_retention_days
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true

  tags = merge(local.common_tags, {
    Name = "${local.managed_db_prefix}-rds"
  })
}

# Managed PostgreSQL (optional): Aurora PostgreSQL (single writer instance)
resource "aws_rds_cluster" "aurora" {
  count = var.postgres_mode == "aurora" ? 1 : 0

  cluster_identifier = "${local.managed_db_prefix}-aurora-cluster"

  engine         = "aurora-postgresql"
  engine_version = var.aurora_engine_version

  database_name   = var.postgres_db_name
  master_username = var.postgres_username
  master_password = local.postgres_password_effective

  db_subnet_group_name   = aws_db_subnet_group.postgres[0].name
  vpc_security_group_ids = [aws_security_group.postgres_managed[0].id]

  backup_retention_period = var.backup_retention_days
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true

  tags = merge(local.common_tags, {
    Name = "${local.managed_db_prefix}-aurora-cluster"
  })
}

resource "aws_rds_cluster_instance" "aurora_writer" {
  count = var.postgres_mode == "aurora" ? 1 : 0

  identifier         = "${local.managed_db_prefix}-aurora-01"
  cluster_identifier = aws_rds_cluster.aurora[0].id

  engine         = aws_rds_cluster.aurora[0].engine
  engine_version = aws_rds_cluster.aurora[0].engine_version
  instance_class = var.aurora_instance_class

  publicly_accessible = false
  apply_immediately   = true

  tags = merge(local.common_tags, {
    Name = "${local.managed_db_prefix}-aurora-01"
  })
}
