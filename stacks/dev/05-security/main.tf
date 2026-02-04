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
  workload_name = "security"
  final_name    = coalesce(var.name, "${var.env}-${var.project}-${local.workload_name}")
  tags = merge(var.tags, {
    Environment = var.env
    Project     = var.project
    ManagedBy   = "terraform"
  })
}

module "security_groups" {
  source   = "../../../modules/security-groups"
  name     = local.final_name
  vpc_id   = try(data.terraform_remote_state.network.outputs.vpc_id, "")
  vpc_cidr = try(data.terraform_remote_state.network.outputs.vpc_cidr, "")

  admin_cidrs      = var.admin_cidrs
  lb_ingress_cidrs = var.lb_ingress_cidrs
  lb_ports         = var.lb_ports

  lb_to_worker_tcp_ports = var.lb_to_worker_tcp_ports

  enable_nodeport_from_lb = var.enable_nodeport_from_lb
  nodeport_from           = var.nodeport_from
  nodeport_to             = var.nodeport_to

  db_ports              = var.db_ports
  allow_db_from_bastion = var.allow_db_from_bastion
  tags                  = local.tags
}
