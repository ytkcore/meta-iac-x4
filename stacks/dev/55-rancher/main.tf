################################################################################
# 55-rancher Stack
# 
# RKE2 클러스터에 Rancher를 설치합니다.
# 순서: 00-network → ... → 50-rke2 → 55-rancher
#
# 글로벌 베스트 프랙티스 권장사항:
# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ Day 1 (초기 부트스트랩): Terraform + Helm Provider                          │
# │ - 인프라 코드와 함께 버전 관리                                               │
# │ - 재현 가능한 설치                                                          │
# │ - 현재 이 스택이 담당                                                       │
# ├─────────────────────────────────────────────────────────────────────────────┤
# │ Day 2 (운영/업그레이드): GitOps (Fleet 또는 ArgoCD) 권장                     │
# │ - Rancher 내장 Fleet 또는 ArgoCD로 전환                                     │
# │ - Helm values를 Git 저장소에서 관리                                         │
# │ - 변경사항 추적 및 롤백 용이                                                 │
# └─────────────────────────────────────────────────────────────────────────────┘
################################################################################

locals {
  _backend_settings = {
    bucket     = var.state_bucket
    region     = var.state_region
    key_prefix = var.state_key_prefix
    azs        = var.azs
  }
}

################################################################################
# Providers
################################################################################

provider "aws" {
  region = var.region
}

# Kubernetes/Helm Provider는 kubeconfig를 통해 RKE2 클러스터에 연결
# 방법 1: Bastion을 통해 kubeconfig 파일 사용
# 방법 2: AWS SSM을 통한 연결
# 방법 3: VPN/Direct Connect를 통한 직접 연결

provider "kubernetes" {
  # Option 1: kubeconfig 파일 사용 (로컬 또는 CI/CD 환경)
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context

  # Option 2: 직접 설정 (exec plugin 등)
  # host                   = data.terraform_remote_state.rke2.outputs.rke2_internal_nlb_dns != null ? "https://${data.terraform_remote_state.rke2.outputs.rke2_internal_nlb_dns}:6443" : null
  # cluster_ca_certificate = var.cluster_ca_certificate
  # token                  = var.cluster_token
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = var.kubeconfig_context
  }
}

provider "kubectl" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context
}

################################################################################
# Remote State References
################################################################################

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.state_region
    key    = "${var.state_key_prefix}/${var.env}/00-network.tfstate"
  }
}

data "terraform_remote_state" "rke2" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.state_region
    key    = "${var.state_key_prefix}/${var.env}/50-rke2.tfstate"
  }
}

# Harbor 연동 (옵션)
data "terraform_remote_state" "harbor" {
  count   = var.use_harbor_registry ? 1 : 0
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.state_region
    key    = "${var.state_key_prefix}/${var.env}/45-harbor.tfstate"
  }
}

################################################################################
# Locals
################################################################################

locals {
  # Harbor 레지스트리 정보 (있으면 사용)
  harbor_registry = var.use_harbor_registry && length(data.terraform_remote_state.harbor) > 0 ? data.terraform_remote_state.harbor[0].outputs.harbor_registry_hostport : null

  common_labels = {
    Project     = var.project
    Environment = var.env
    ManagedBy   = "terraform"
    Stack       = "55-rancher"
  }
}

################################################################################
# Rancher Module
################################################################################

module "rancher" {
  source = "../../../modules/rancher"

  # 필수 입력 (스택에서 받음)
  project = var.project
  env     = var.env
  domain  = var.domain

  # Rancher 초기 관리자 비밀번호
  bootstrap_password = var.bootstrap_password

  # 옵션: Harbor 사용 시 자동 연동
  private_registry = local.harbor_registry != null ? local.harbor_registry : var.private_registry

  # 공통 라벨
  labels = local.common_labels
}
