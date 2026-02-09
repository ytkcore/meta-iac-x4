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
resource "random_password" "neo4j" {
  length  = 24
  special = false
}

locals {
  neo4j_password_effective = coalesce(var.neo4j_password, random_password.neo4j.result)
}

# ------------------------------------------------------------------------------
# Neo4j Instance
# ------------------------------------------------------------------------------
module "neo4j" {
  source = "../../../modules/neo4j-standalone"

  name    = "neo4j"
  env     = var.env
  project = var.project

  vpc_id    = module.common.vpc_id
  vpc_cidr  = module.common.vpc_cidr
  subnet_id = module.common.db_subnet_ids["c"]

  instance_type       = var.instance_type
  root_volume_size_gb = var.root_volume_gb

  neo4j_image_tag = var.neo4j_image_tag
  neo4j_password  = local.neo4j_password_effective

  allowed_sg_ids      = module.common.allowed_sgs
  allowed_cidr_blocks = module.common.allowed_cidrs

  tags = merge(local.common_tags, { Role = "neo4j" })

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
resource "aws_route53_record" "neo4j" {
  count   = module.common.route53_zone_id != "" ? 1 : 0
  zone_id = module.common.route53_zone_id
  name    = "neo4j.${var.env}.${module.common.base_domain}"
  type    = "A"
  ttl     = 300
  records = [module.neo4j.private_ip]

  allow_overwrite = true

  depends_on = [
    module.neo4j
  ]
}
