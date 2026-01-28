locals {
  # backend 관련 변수들을 "사용"한 것으로 처리하여 경고/린트 노이즈를 줄입니다.
  # (terraform init backend-config 값은 Makefile에서 주입하지만, env.tfvars에 함께 들어오는 경우가 있어 선언/참조를 유지합니다.)
  _backend_settings = {
    bucket     = var.state_bucket
    region     = var.state_region
    key_prefix = var.state_key_prefix
    azs        = var.azs
  }
}

# 00-network 스택의 출력값(VPC/서브넷/라우팅 정보)을 참조합니다.
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

  # tier별 서브넷 목록(00-network outputs)
  subnet_ids_by_tier = data.terraform_remote_state.network.outputs.subnet_ids_by_tier

  # Interface Endpoint를 배치할 서브넷(tier) 목록을 받아, 실제 subnet id 배열로 변환합니다.
  interface_subnet_ids = flatten([
    for t in var.interface_subnet_tiers : lookup(local.subnet_ids_by_tier, t, [])
  ])
}

# ---------------------------------------------------------------------------
# Interface Endpoint용 보안그룹 (옵션)
# - security 스택 상태값이 없어도 endpoints 스택 단독으로 plan/apply 가능하도록,
#   vpce_security_group_id가 null이면 여기서 기본 SG를 생성합니다.
# - 기본 정책: VPC CIDR에서 443(TCP)만 허용, egress는 전체 허용(Endpoint ENI 기본 동작)
# ---------------------------------------------------------------------------
resource "aws_security_group" "vpce" {
  count       = var.enable_interface_endpoints && var.vpce_security_group_id == null ? 1 : 0
  name_prefix = "${var.name}-vpce-"
  description = "Interface VPC Endpoint SG (443 from VPC CIDR)"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  ingress {
    description = "HTTPS from VPC CIDR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.terraform_remote_state.network.outputs.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

locals {
  # Interface Endpoint가 활성화된 경우에만 SG를 전달합니다.
  vpce_sg_id  = var.vpce_security_group_id != null ? var.vpce_security_group_id : try(aws_security_group.vpce[0].id, null)
  vpce_sg_ids = var.enable_interface_endpoints ? compact([local.vpce_sg_id]) : []
}

module "endpoints" {
  source = "../../../modules/vpc-endpoints"

  name                       = var.name
  region                     = var.region
  vpc_id                     = data.terraform_remote_state.network.outputs.vpc_id
  enable_interface_endpoints = var.enable_interface_endpoints

  interface_services   = var.interface_services
  interface_subnet_ids = local.interface_subnet_ids
  security_group_ids   = local.vpce_sg_ids

  tags = local.tags
}
