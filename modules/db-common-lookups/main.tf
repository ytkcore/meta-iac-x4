# ------------------------------------------------------------------------------
# DB Common Lookups Module
# Provides shared remote state lookups and configuration for all DB stacks
# ------------------------------------------------------------------------------

locals {
  stack_network  = "00-network"
  stack_security = "05-security"
  stack_harbor   = "40-harbor"

  key_network  = "${var.state_key_prefix}/${var.env}/${local.stack_network}.tfstate"
  key_security = "${var.state_key_prefix}/${var.env}/${local.stack_security}.tfstate"
  key_harbor   = "${var.state_key_prefix}/${var.env}/${local.stack_harbor}.tfstate"
}

# ------------------------------------------------------------------------------
# Remote States
# ------------------------------------------------------------------------------
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.state_region
    key    = local.key_network
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

data "terraform_remote_state" "harbor" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.state_region
    key    = local.key_harbor
  }
}

# ------------------------------------------------------------------------------
# Local Variables & Subnet Mapping
# ------------------------------------------------------------------------------
locals {
  vpc_id   = try(data.terraform_remote_state.network.outputs.vpc_id, "")
  vpc_cidr = try(data.terraform_remote_state.network.outputs.vpc_cidr, "")

  # Subnets categorized by Tier and AZ
  all_subnet_ids = try(data.terraform_remote_state.network.outputs.subnet_ids, {})

  # DB subnet IDs by AZ
  db_subnet_ids = {
    a = try(local.all_subnet_ids["db-pri-a"], "")
    c = try(local.all_subnet_ids["db-pri-c"], "")
  }

  # Harbor configuration
  harbor_registry_hostport = try(data.terraform_remote_state.harbor.outputs.harbor_registry_hostport, "")
  harbor_scheme            = try(data.terraform_remote_state.harbor.outputs.harbor_scheme, "https")
  harbor_project           = try(data.terraform_remote_state.harbor.outputs.harbor_proxy_cache_project, "library")

  # Logical Identity SGs (Static identity from 05-security)
  k8s_client_sg_id = try(data.terraform_remote_state.security.outputs.k8s_client_sg_id, "")
  ops_client_sg_id = try(data.terraform_remote_state.security.outputs.ops_client_sg_id, "")

  # K8s Node Subnet CIDRs (Logical location from 00-network)
  k8s_subnet_cidrs = try(data.terraform_remote_state.network.outputs.subnet_cidrs_by_tier["k8s_dp"], [])

  # Allowed access lists
  allowed_cidrs = distinct(concat([local.vpc_cidr], local.k8s_subnet_cidrs))
  allowed_sgs   = compact([local.k8s_client_sg_id, local.ops_client_sg_id])

  # Private DNS Integration
  route53_zone_id = try(data.terraform_remote_state.network.outputs.route53_zone_id, "")
  base_domain     = try(data.terraform_remote_state.network.outputs.base_domain, var.base_domain)
}
