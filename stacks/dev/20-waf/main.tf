provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  name_prefix = "${var.env}-${var.project}"

  common_tags = merge(
    {
      Environment = var.env
      Project     = var.project
      ManagedBy   = "terraform"
      Stack       = "20-waf"
    },
    var.tags
  )
}

# -----------------------------------------------------------------------------
# Remote State (Teleport)
# -----------------------------------------------------------------------------
data "terraform_remote_state" "teleport" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.state_key_prefix}/${var.env}/15-teleport.tfstate"
    region = var.state_region
  }
}

# -----------------------------------------------------------------------------
# WAF Module
# -----------------------------------------------------------------------------
module "teleport_waf" {
  source = "../../../modules/waf-acl"

  name       = "${local.name_prefix}-teleport-waf"
  alb_arn    = data.terraform_remote_state.teleport.outputs.alb_arn
  rate_limit = var.rate_limit

  tags = local.common_tags
}
