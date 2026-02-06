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

# -----------------------------------------------------------------------------
# 3. App Module (Teleport)
# -----------------------------------------------------------------------------
# Conditionally load app based on variable (future extensibility)
module "app" {
  source = "../../../modules/apps/teleport"

  name                  = "${var.project}-${var.env}-teleport"
  region                = var.aws_region
  vpc_id                = data.terraform_remote_state.network.outputs.vpc_id
  vpc_cidr              = data.terraform_remote_state.network.outputs.vpc_cidr
  alb_security_group_id = module.alb.security_group_id
  listener_arn          = module.alb.https_listener_arn
  domain_name           = "teleport.${var.base_domain}"
  cluster_name          = "teleport.${var.base_domain}"
  teleport_version      = "18.6.6"
  base_domain           = var.base_domain
  environment           = var.env

  tags = {
    Environment = var.env
    Project     = var.project
    Stack       = "15-access-control"
  }
}

# -----------------------------------------------------------------------------
# 4. EC2 Module (Compute)
# -----------------------------------------------------------------------------
module "ec2" {
  source = "../../../modules/ec2-instance"

  # Single instance config (or HA if needed)
  name    = "${local.name_prefix}-ec2"
  env     = var.env
  project = var.project
  region  = var.aws_region

  subnet_id              = data.terraform_remote_state.network.outputs.subnet_ids_by_tier["public"][0]
  vpc_security_group_ids = [module.app.security_group_id]
  instance_type          = "t3.medium"
  root_volume_size       = 50

  # Inject Logic from App Module
  user_data            = module.app.user_data
  iam_instance_profile = module.app.iam_instance_profile_name

  # Golden Image Support
  state_bucket     = var.state_bucket
  state_region     = var.aws_region
  state_key_prefix = var.state_key_prefix
}

# -----------------------------------------------------------------------------
# 5. Glue: Connect EC2 to Target Groups
# -----------------------------------------------------------------------------
resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = module.app.web_target_group_arn
  target_id        = module.ec2.instance_id
  port             = 3080
}


