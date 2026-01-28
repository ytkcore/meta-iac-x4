locals {
  # Touch backend-related variables so Terraform/tflint see them as "used".
  _backend_settings = {
    bucket     = var.state_bucket
    region     = var.state_region
    key_prefix = var.state_key_prefix
  }
}


module "vpc" {
  source = "../../../modules/vpc"
  name   = var.name
  cidr   = var.vpc_cidr
  tags   = local.tags
}

module "igw" {
  source = "../../../modules/igw"
  name   = var.name
  vpc_id = module.vpc.vpc_id
  tags   = local.tags
}

module "subnets" {
  source  = "../../../modules/subnets"
  name    = var.name
  vpc_id  = module.vpc.vpc_id
  subnets = var.subnets
  tags    = local.tags
}

locals {
  tags = merge(var.tags, {
    Environment = var.env
    Project     = var.project
  })
  subnet_ids = module.subnets.subnet_ids

  public_subnet_ids = [for k, v in var.subnets : local.subnet_ids[k] if v.tier == "public"]

  public_subnet_id_by_az = {
    for k, v in var.subnets :
    v.az => local.subnet_ids[k]
    if v.tier == "public"
  }

  # NOTE:
  # - "private" 라우트 테이블(= NAT egress)을 적용할 서브넷 목록입니다.
  # - DB 서브넷은 별도 db_route_table로 분리되어 enable_nat_for_db 옵션으로 제어합니다.
  # - 따라서 public=false 이면서 tier!=db 인 서브넷은 모두 NAT egress 대상입니다.
  private_subnet_ids_by_az = {
    for az in var.azs :
    az => [for k, v in var.subnets : local.subnet_ids[k] if v.az == az && v.public == false && v.tier != "db"]
  }

  db_subnet_ids_by_az = {
    for az in var.azs :
    az => [for k, v in var.subnets : local.subnet_ids[k] if v.az == az && v.tier == "db"]
  }
}

module "nat" {
  source                 = "../../../modules/nat"
  name                   = var.name
  public_subnet_id_by_az = var.enable_nat ? local.public_subnet_id_by_az : {}
  tags                   = local.tags
}

module "routing" {
  source = "../../../modules/routing"
  name   = var.name
  vpc_id = module.vpc.vpc_id
  igw_id = module.igw.igw_id

  public_subnet_ids        = local.public_subnet_ids
  private_subnet_ids_by_az = local.private_subnet_ids_by_az
  db_subnet_ids_by_az      = local.db_subnet_ids_by_az

  enable_nat           = var.enable_nat
  enable_nat_for_db    = var.enable_nat_for_db
  nat_gateway_id_by_az = module.nat.nat_gateway_id_by_az
  tags                 = local.tags
}

# ---------------------------------------------------------------------------
# Gateway VPC Endpoints (기본: S3 + DynamoDB)
# - 네트워크 기반에 속하는 리소스로 보고 00-network에서 함께 생성합니다.
# - for_each 키(서비스명)는 plan 시점에 고정, route_table_ids 값은 apply 시점에 확정되어도 문제 없습니다.
# ---------------------------------------------------------------------------
locals {
  gateway_route_table_ids = distinct(concat(
    values(module.routing.private_route_table_ids_by_az),
    values(module.routing.db_route_table_ids_by_az)
  ))
}

resource "aws_vpc_endpoint" "gateway" {
  for_each          = var.enable_gateway_endpoints ? toset(var.gateway_services) : toset([])
  vpc_id            = module.vpc.vpc_id
  vpc_endpoint_type = "Gateway"
  service_name      = "com.amazonaws.${var.region}.${each.value}"
  route_table_ids   = local.gateway_route_table_ids

  tags = merge(local.tags, {
    Name    = "${var.name}-vpce-gw-${each.value}"
    Type    = "gateway"
    Service = each.value
  })
}
