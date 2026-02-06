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
resource "random_password" "opensearch" {
  length  = 16
  special = true
  # OpenSearch requires: min 8 chars, uppercase, lowercase, number, special char
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
  min_special = 1
}

locals {
  admin_password_effective = coalesce(var.admin_password, random_password.opensearch.result)
}

# ------------------------------------------------------------------------------
# OpenSearch Instance
# ------------------------------------------------------------------------------
module "opensearch" {
  source = "../../../modules/opensearch-standalone"

  name    = "opensearch"
  env     = var.env
  project = var.project

  vpc_id    = module.common.vpc_id
  vpc_cidr  = module.common.vpc_cidr
  subnet_id = module.common.db_subnet_ids["a"]

  instance_type       = var.instance_type
  root_volume_size_gb = var.root_volume_gb

  opensearch_image_tag = var.opensearch_image_tag
  dashboards_image_tag = var.dashboards_image_tag
  admin_password       = local.admin_password_effective

  allowed_sg_ids      = module.common.allowed_sgs
  allowed_cidr_blocks = module.common.allowed_cidrs

  tags = merge(local.common_tags, { Role = "opensearch" })

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
# Private DNS Records
# ------------------------------------------------------------------------------
resource "aws_route53_record" "opensearch" {
  count   = module.common.route53_zone_id != "" ? 1 : 0
  zone_id = module.common.route53_zone_id
  name    = "opensearch.${var.env}.${module.common.base_domain}"
  type    = "A"
  ttl     = 300
  records = [module.opensearch.private_ip]

  allow_overwrite = true

  depends_on = [
    module.opensearch
  ]
}

resource "aws_route53_record" "opensearch_dashboards" {
  count   = module.common.route53_zone_id != "" ? 1 : 0
  zone_id = module.common.route53_zone_id
  name    = "opensearch-dashboards.${var.env}.${module.common.base_domain}"
  type    = "A"
  ttl     = 300
  records = [module.opensearch.private_ip]

  allow_overwrite = true

  depends_on = [
    module.opensearch
  ]
}
