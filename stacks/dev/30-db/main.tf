locals {
  # Touch backend-related variables so Terraform/tflint see them as "used".
  _backend_settings = {
    bucket     = var.state_bucket
    region     = var.state_region
    key_prefix = var.state_key_prefix
    azs        = var.azs
  }
}


data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket  = var.state_bucket
    key     = "${var.state_key_prefix}/${var.env}/00-network.tfstate"
    region  = var.state_region
    encrypt = true
  }
}

locals {
  tags = merge(var.tags, {
    Environment = var.env
    Project     = var.project
  })
  subnet_ids_by_tier = data.terraform_remote_state.network.outputs.subnet_ids_by_tier
  db_subnet_ids      = lookup(local.subnet_ids_by_tier, "db", [])
  db_subnet_group    = coalesce(var.db_subnet_group_name, "${var.name}-db-subnet-group")
}

module "db_subnet_group" {
  source     = "../../../modules/db-subnet-group"
  name       = local.db_subnet_group
  subnet_ids = local.db_subnet_ids
  tags       = local.tags
}
