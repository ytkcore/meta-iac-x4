# ==============================================================================
# Network Stack Configuration
#
# Description:
#   - Instantiates the unified "network" module.
#   - Defines the core network infrastructure (VPC, Subnets, Routing, NAT/IGW).
#
# Maintainer: DevOps Team
# ==============================================================================

locals {
  # Touch backend-related variables so Terraform/tflint see them as "used".
  _backend_settings = {
    bucket     = var.state_bucket
    region     = var.state_region
    key_prefix = var.state_key_prefix
  }
}

module "network" {
  source = "../../../modules/vpc"

  env                      = var.env
  project                  = var.project
  region                   = var.region
  vpc_cidr                 = var.vpc_cidr
  azs                      = var.azs
  subnets                  = var.subnets
  enable_nat               = var.enable_nat
  enable_nat_for_db        = var.enable_nat_for_db
  enable_gateway_endpoints = var.enable_gateway_endpoints
  gateway_services         = var.gateway_services
}
