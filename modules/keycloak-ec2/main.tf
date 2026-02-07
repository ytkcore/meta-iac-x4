# ==============================================================================
# Keycloak EC2 Module
#
# Keycloak Identity Provider — Docker Compose on Golden Image EC2
# - SSO (Grafana, ArgoCD, Rancher, Harbor, Teleport)
# - Workload OIDC (Keycloak → AWS IAM STS)
# - External PostgreSQL for persistent state
# ==============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# 1. Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "keycloak" {
  name        = "${var.name}-sg"
  description = "Security Group for Keycloak IdP"
  vpc_id      = var.vpc_id

  # HTTPS (8443) — Keycloak 기본 HTTPS 포트
  ingress {
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Keycloak HTTPS from VPC"
  }

  # HTTP (8080) — Health check / 내부 통신
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Keycloak HTTP (health check)"
  }

  # K8s 노드에서 접근 허용 (OIDC token validation)
  dynamic "ingress" {
    for_each = var.allowed_sg_ids
    content {
      from_port       = 8443
      to_port         = 8443
      protocol        = "tcp"
      security_groups = [ingress.value]
      description     = "Keycloak HTTPS from K8s/allowed SGs"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all egress"
  }

  tags = merge(var.tags, { Name = "${var.name}-sg" })
}

# -----------------------------------------------------------------------------
# 2. User Data (Docker Compose + Keycloak)
# -----------------------------------------------------------------------------

locals {
  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    keycloak_version        = var.keycloak_version
    keycloak_admin_user     = var.keycloak_admin_user
    keycloak_admin_password = var.keycloak_admin_password
    keycloak_hostname       = var.keycloak_hostname
    db_host                 = var.db_host
    db_port                 = var.db_port
    db_name                 = var.db_name
    db_username             = var.db_username
    db_password             = var.db_password
    harbor_registry         = var.harbor_registry_hostport
    harbor_scheme           = var.harbor_scheme
  })
}

# -----------------------------------------------------------------------------
# 3. EC2 Instance (Golden Image)
# -----------------------------------------------------------------------------

module "instance" {
  source = "../ec2-instance"

  name    = "keycloak"
  env     = var.env
  project = var.project
  region  = var.region

  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.keycloak.id]
  instance_type          = var.instance_type
  root_volume_size       = var.root_volume_size_gb

  user_data = local.user_data

  # Golden Image
  state_bucket       = var.state_bucket
  state_region       = var.state_region
  state_key_prefix   = var.state_key_prefix
  ami_id             = var.ami_id
  allow_ami_fallback = var.allow_ami_fallback

  tags = merge(var.tags, { Role = "keycloak" })
}

# SSM Policy (ec2-instance 모듈의 IAM Role에 SSM 접근 허용)
resource "aws_iam_role_policy_attachment" "ssm" {
  count      = module.instance.iam_role_name != null ? 1 : 0
  role       = module.instance.iam_role_name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
