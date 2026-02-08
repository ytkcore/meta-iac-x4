# =============================================================================
# 80-access-gateway Stack - Main
# =============================================================================
# 
# 이 스택은 모든 서비스 스택에서 service_endpoint를 수집하고
# 선택된 접근 제어 솔루션(Teleport/Boundary)에 등록합니다.
# 
# 솔루션 독립적: 서비스 스택은 특정 접근 제어 솔루션에 의존하지 않습니다.
# =============================================================================

provider "aws" {
  region = var.region
}

locals {
  name_prefix = "${var.env}-${var.project}"
}

# =============================================================================
# Remote State - Access Control (Teleport Server)
# =============================================================================
data "terraform_remote_state" "access_control" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.state_key_prefix}/${var.env}/15-access-control.tfstate"
    region = var.state_region
  }
}

# =============================================================================
# Remote State - Service Endpoints (EC2 기반 서비스)
# =============================================================================

data "terraform_remote_state" "harbor" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.state_key_prefix}/${var.env}/40-harbor.tfstate"
    region = var.state_region
  }
}

data "terraform_remote_state" "neo4j" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.state_key_prefix}/${var.env}/61-neo4j.tfstate"
    region = var.state_region
  }
}

data "terraform_remote_state" "opensearch" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.state_key_prefix}/${var.env}/62-opensearch.tfstate"
    region = var.state_region
  }
}

# =============================================================================
# Service Collection
# =============================================================================

locals {
  # EC2 기반 서비스 (자동 수집)
  ec2_services = [
    try(data.terraform_remote_state.harbor.outputs.service_endpoint, null),
    try(data.terraform_remote_state.neo4j.outputs.service_endpoint, null),
    try(data.terraform_remote_state.opensearch.outputs.service_endpoint, null),
  ]

  # K8s 기반 서비스 (변수로 지정)
  k8s_services = var.kubernetes_services

  # 전체 서비스 목록 (null 제외)
  all_services = concat(
    [for s in local.ec2_services : s if s != null],
    local.k8s_services
  )
}

# =============================================================================
# Teleport Integration (access_solution = "teleport")
# =============================================================================

module "teleport_apps" {
  source = "../../../modules/access-gateway/teleport"
  count  = var.access_solution == "teleport" ? 1 : 0

  services        = local.all_services
  teleport_server = data.terraform_remote_state.access_control.outputs.teleport_server
  region          = var.region
}
