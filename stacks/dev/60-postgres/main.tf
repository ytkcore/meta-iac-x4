provider "aws" {
  region = var.region
}

locals {
  common_tags = {
    ManagedBy   = "terraform"
    Project     = var.project
    Environment = var.env
  }
}

# ------------------------------------------------------------------------------
# Common Lookups Module
# ------------------------------------------------------------------------------
module "common" {
  source = "../../../modules/db-common-lookups"

  env              = var.env
  state_bucket     = var.state_bucket
  state_region     = var.state_region
  state_key_prefix = var.state_key_prefix
  base_domain      = var.base_domain
}

# ------------------------------------------------------------------------------
# Credentials
# ------------------------------------------------------------------------------
resource "random_password" "postgres" {
  length  = 24
  special = false
}

locals {
  postgres_password_effective = coalesce(var.postgres_password, random_password.postgres.result)
}

# ------------------------------------------------------------------------------
# PostgreSQL Instance
# ------------------------------------------------------------------------------
module "postgres" {
  source = "../../../modules/postgres-standalone"

  name    = "postgres"
  env     = var.env
  project = var.project

  vpc_id    = module.common.vpc_id
  vpc_cidr  = module.common.vpc_cidr
  subnet_id = module.common.db_subnet_ids["a"]

  instance_type       = var.instance_type
  root_volume_size_gb = var.root_volume_gb

  postgres_image_tag = var.postgres_image_tag
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = local.postgres_password_effective

  allowed_sg_ids      = module.common.allowed_sgs
  allowed_cidr_blocks = module.common.allowed_cidrs

  tags = merge(local.common_tags, { Role = "postgres" })

  # Golden Image
  state_bucket     = var.state_bucket
  state_region     = var.state_region
  state_key_prefix = var.state_key_prefix
  ami_id           = var.ami_id

  # Harbor
  harbor_registry_hostport = module.common.harbor_registry_hostport
  harbor_scheme            = module.common.harbor_scheme
  harbor_project           = module.common.harbor_project
  harbor_insecure          = true
}

# ------------------------------------------------------------------------------
# Private DNS Record
# ------------------------------------------------------------------------------
resource "aws_route53_record" "postgres" {
  count   = module.common.route53_zone_id != "" ? 1 : 0
  zone_id = module.common.route53_zone_id
  name    = "postgres.${var.env}.${module.common.base_domain}"
  type    = "A"
  ttl     = 300
  records = [module.postgres.private_ip]

  allow_overwrite = true

  depends_on = [
    module.postgres
  ]
}
