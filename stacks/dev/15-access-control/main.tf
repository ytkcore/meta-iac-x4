terraform {
  backend "s3" {
    bucket         = "meta-terraform-state-ap-northeast-2-599913747911"
    key            = "dev/15-access-control/terraform.tfstate"
    region         = "ap-northeast-2"
    encrypt        = true
    dynamodb_table = "meta-terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  name_prefix = "${var.project}-${var.env}-access"
}

# -----------------------------------------------------------------------------
# 0. Remote State
# -----------------------------------------------------------------------------
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.state_key_prefix}/${var.env}/00-network.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "security" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.state_key_prefix}/${var.env}/05-security.tfstate"
    region = var.aws_region
  }
}

# -----------------------------------------------------------------------------
# 1. DNS & Certificate
# -----------------------------------------------------------------------------
data "aws_route53_zone" "main" {
  name = var.base_domain
}

# Private Zone for Split-Horizon DNS (Internal Access)
data "aws_route53_zone" "private" {
  name         = var.base_domain
  private_zone = true
  vpc_id       = data.terraform_remote_state.network.outputs.vpc_id
}

resource "aws_acm_certificate" "this" {
  domain_name       = "teleport.${var.base_domain}"
  validation_method = "DNS"
  subject_alternative_names = ["*.teleport.${var.base_domain}"]

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${local.name_prefix}-cert"
    Environment = var.env
    Project     = var.project
    Stack       = "15-access-control"
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# -----------------------------------------------------------------------------
# 2. Public ALB Module
# -----------------------------------------------------------------------------
module "alb" {
  source = "../../../modules/alb-public"

  name            = "${local.name_prefix}-alb"
  vpc_id          = data.terraform_remote_state.network.outputs.vpc_id
  subnet_ids      = data.terraform_remote_state.network.outputs.subnet_ids_by_tier["public"]
  certificate_arn = aws_acm_certificate.this.arn

  tags = {
    Environment = var.env
    Project     = var.project
    Stack       = "15-access-control"
  }
}

resource "aws_route53_record" "alb" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "teleport.${var.base_domain}"
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

# Wildcard record for Application Access (e.g., harbor.teleport.unifiedmeta.net)
resource "aws_route53_record" "alb_wildcard" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "*.teleport.${var.base_domain}"
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

# -----------------------------------------------------------------------------
# Private DNS Records (Split-Horizon Support)
# -----------------------------------------------------------------------------

resource "aws_route53_record" "alb_private" {
  zone_id = data.aws_route53_zone.private.zone_id
  name    = "teleport.${var.base_domain}"
  type    = "CNAME"
  ttl     = 300
  records = [module.alb.alb_dns_name]
}

resource "aws_route53_record" "alb_wildcard_private" {
  zone_id = data.aws_route53_zone.private.zone_id
  name    = "*.teleport.${var.base_domain}"
  type    = "CNAME"
  ttl     = 300
  records = [module.alb.alb_dns_name]
}

# =============================================================================
# 3. Access Control Solution (Pluggable)
# =============================================================================
# var.access_solution 으로 프로비저닝 솔루션 선택:
#   "teleport" (default) → modules/teleport-ec2
#   "none"               → 프로비저닝 없음

# -----------------------------------------------------------------------------
# 3-A. Teleport (Default)
# -----------------------------------------------------------------------------
module "teleport" {
  source = "../../../modules/teleport-ec2"
  count  = var.access_solution == "teleport" ? 1 : 0

  name       = "${var.project}-${var.env}-teleport"
  region     = var.aws_region
  vpc_id     = data.terraform_remote_state.network.outputs.vpc_id
  vpc_cidr   = data.terraform_remote_state.network.outputs.vpc_cidr
  subnet_ids = data.terraform_remote_state.network.outputs.subnet_ids_by_tier["public"]
  env        = var.env
  project    = var.project

  # Teleport Config
  cluster_name     = "teleport.${var.base_domain}"
  base_domain      = var.base_domain
  teleport_version = "18.6.6"
  email            = "admin@${var.base_domain}"

  # ALB Integration
  alb_security_group_ids = [module.alb.security_group_id]
  listener_arn           = module.alb.https_listener_arn
  domain_name            = "teleport.${var.base_domain}"

  # Golden Image Support
  state_bucket     = var.state_bucket
  state_region     = var.aws_region
  state_key_prefix = var.state_key_prefix

  tags = {
    Environment = var.env
    Project     = var.project
    Stack       = "15-access-control"
  }
}
