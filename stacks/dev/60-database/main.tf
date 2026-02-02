terraform {
  backend "s3" {}
}

provider "aws" {
  region = var.region
}

# ------------------------------------------------------------------------------
# Network Lookup
# ------------------------------------------------------------------------------
data "aws_vpc" "selected" {
  filter {
    name   = "tag:Name"
    values = ["*${var.env}*"]
  }
  state = "available"
}

locals {
  vpc_id         = data.aws_vpc.selected.id
  vpc_cidr_block = data.aws_vpc.selected.cidr_block
}

# ------------------------------------------------------------------------------
# Lookup DB Subnets
# ------------------------------------------------------------------------------
data "aws_subnets" "db" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  filter {
    name   = "tag:Name"
    values = ["*db*", "*database*"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  filter {
    name   = "tag:Name"
    values = ["*private*"]
  }
}

locals {
  target_subnets = length(data.aws_subnets.db.ids) > 0 ? data.aws_subnets.db.ids : data.aws_subnets.private.ids
}

data "aws_subnet" "selected" {
  for_each = toset(local.target_subnets)
  id       = each.value
}

locals {
  subnet_a = [for s in data.aws_subnet.selected : s.id if can(regex("a$", s.availability_zone))][0]
  subnet_c = [for s in data.aws_subnet.selected : s.id if can(regex("c$", s.availability_zone))][0]
}

# ------------------------------------------------------------------------------
# Security Groups
# ------------------------------------------------------------------------------
resource "aws_security_group" "db_sg" {
  name        = "db-standalone-sg-${var.env}"
  description = "Security group for Standalone DBs"
  vpc_id      = local.vpc_id

  # PostgreSQL
  ingress {
    description = "PostgreSQL from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
  }

  # Neo4j
  ingress {
    description = "Neo4j HTTP from VPC"
    from_port   = 7474
    to_port     = 7474
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
  }

  ingress {
    description = "Neo4j Bolt from VPC"
    from_port   = 7687
    to_port     = 7687
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
  }

  # ICMP
  ingress {
    description = "ICMP from VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [local.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "db-standalone-sg-${var.env}"
  }
}

# ------------------------------------------------------------------------------
# EC2 Instances (Using ec2-instance module & Golden Image)
# ------------------------------------------------------------------------------

module "postgres" {
  source = "../../../modules/ec2-instance"

  name          = "postgres"
  env           = var.env
  project       = var.project
  instance_type = var.instance_type_postgres
  subnet_id     = local.subnet_a

  vpc_security_group_ids = [aws_security_group.db_sg.id]
  key_name               = var.key_name

  user_data = templatefile("${path.module}/templates/user-data-db.sh.tftpl", {
    db_type      = "postgres"
    docker_image = "my-harbor.local/library/postgres:17-alpine"
    db_password  = var.postgres_password
    compose_yml  = file("${path.module}/docker/docker-compose.yml")
    pg_hba_conf  = file("${path.module}/docker/config/postgres/pg_hba.conf")
    setup_sh     = file("${path.module}/docker/setup.sh")
    neo4j_conf   = ""
  })
}

module "neo4j" {
  source = "../../../modules/ec2-instance"

  name          = "neo4j"
  env           = var.env
  project       = var.project
  instance_type = var.instance_type_neo4j
  subnet_id     = local.subnet_c

  vpc_security_group_ids = [aws_security_group.db_sg.id]
  key_name               = var.key_name

  user_data = templatefile("${path.module}/templates/user-data-db.sh.tftpl", {
    db_type      = "neo4j"
    docker_image = "my-harbor.local/library/neo4j:5.26-enterprise"
    db_password  = var.neo4j_password
    compose_yml  = file("${path.module}/docker/docker-compose.yml")
    pg_hba_conf  = ""
    setup_sh     = file("${path.module}/docker/setup.sh")
    neo4j_conf   = file("${path.module}/docker/config/neo4j/neo4j.conf")
  })
}
