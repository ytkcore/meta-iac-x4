locals {
  # backend 관련 변수들을 "사용"한 것으로 처리하여 경고/린트 노이즈를 줄입니다.
  _backend_settings = {
    bucket     = var.state_bucket
    region     = var.state_region
    key_prefix = var.state_key_prefix
    azs        = var.azs
  }

  workload_name = "k8s"
  name          = "${var.project}-${var.env}-${local.workload_name}"
  common_tags = {
    ManagedBy   = "terraform"
    Project     = var.project
    Environment = var.env
  }
}

provider "aws" {
  region = var.region
}

# 00-network 스택의 출력값(VPC/서브넷 등)을 참조합니다.
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.state_region
    key    = "${var.state_key_prefix}/${var.env}/00-network.tfstate"
  }
}

data "terraform_remote_state" "security" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.state_region
    key    = "${var.state_key_prefix}/${var.env}/05-security.tfstate"
  }
}

################################################################################
# Harbor tfstate 존재 여부 자동 감지 (S3 key 존재 여부 기반)
################################################################################

data "aws_s3_objects" "harbor_tfstate" {
  bucket = var.state_bucket
  prefix = "${var.state_key_prefix}/${var.env}/40-harbor.tfstate"
}

locals {
  harbor_tfstate_found = length(try(data.aws_s3_objects.harbor_tfstate.keys, [])) > 0
  effective_use_harbor = var.use_harbor || (var.auto_use_harbor_if_state_exists && local.harbor_tfstate_found)
}

# ################################################################################
# # ACM Configuration
# # - ACM Certificate ARN from Network stack or Var
# ################################################################################

locals {
  # 최종 인증서 ARN 결정 (Priority: 스택 변수 > 네트워크 스택 출력)
  network_acm_arn               = try(data.terraform_remote_state.network.outputs.acm_certificate_arn, "")
  effective_acm_certificate_arn = coalesce(var.acm_certificate_arn, local.network_acm_arn, "null") == "null" ? null : coalesce(var.acm_certificate_arn, local.network_acm_arn)

  effective_enable_acm_tls_termination = var.enable_acm_tls_termination && (local.effective_acm_certificate_arn != null)
}

# ################################################################################
# # ExternalDNS Scoped Policy (Global Standard: Least Privilege)
# # - Allows updating only the specific Hosted Zone (base_domain).
# # ################################################################################

data "aws_route53_zone" "public" {
  count        = var.base_domain != "" ? 1 : 0
  name         = var.base_domain
  private_zone = false
}

data "aws_route53_zone" "private" {
  count        = var.base_domain != "" ? 1 : 0
  name         = var.base_domain
  private_zone = true
  vpc_id       = data.terraform_remote_state.network.outputs.vpc_id
}

resource "aws_iam_policy" "external_dns" {
  count       = var.base_domain != "" ? 1 : 0
  name        = "${var.env}-${var.project}-external-dns-policy"
  description = "Scoped permissions for ExternalDNS to manage specific Route53 zone"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["route53:ChangeResourceRecordSets"]
        Resource = compact([
          try("arn:aws:route53:::hostedzone/${data.aws_route53_zone.public[0].zone_id}", ""),
          try("arn:aws:route53:::hostedzone/${data.aws_route53_zone.private[0].zone_id}", "")
        ])
      },
      {
        Effect   = "Allow"
        Action   = ["route53:ListHostedZones", "route53:ListResourceRecordSets"]
        Resource = "*"
      },
      # Required for cert-manager DNS-01 challenge to verify TXT record propagation
      {
        Effect   = "Allow"
        Action   = ["route53:GetChange"]
        Resource = "arn:aws:route53:::change/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  count      = var.base_domain != "" ? 1 : 0
  role       = module.rke2.iam_role_name
  policy_arn = aws_iam_policy.external_dns[0].arn
}

# Harbor remote state (선택적)
data "terraform_remote_state" "harbor" {
  count   = local.effective_use_harbor ? 1 : 0
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.state_region
    key    = "${var.state_key_prefix}/${var.env}/40-harbor.tfstate"
  }
}

locals {
  vpc_id   = try(data.terraform_remote_state.network.outputs.vpc_id, "")
  vpc_cidr = try(data.terraform_remote_state.network.outputs.vpc_cidr, "")

  # subnets 모듈에서 tier 별로 모아둔 값을 그대로 사용합니다.
  subnet_ids_by_tier = try(data.terraform_remote_state.network.outputs.subnet_ids_by_tier, {})

  # Harbor 설정 (선택적) - Harbor가 없으면 null 사용
  harbor_hostname      = local.effective_use_harbor && length(data.terraform_remote_state.harbor) > 0 ? try(data.terraform_remote_state.harbor[0].outputs.harbor_hostname, null) : null
  harbor_private_ip    = local.effective_use_harbor && length(data.terraform_remote_state.harbor) > 0 ? try(data.terraform_remote_state.harbor[0].outputs.harbor_private_ip, null) : null
  harbor_scheme        = local.effective_use_harbor && length(data.terraform_remote_state.harbor) > 0 ? try(data.terraform_remote_state.harbor[0].outputs.harbor_scheme, "http") : "http"
  harbor_proxy_project = local.effective_use_harbor && length(data.terraform_remote_state.harbor) > 0 ? try(data.terraform_remote_state.harbor[0].outputs.harbor_proxy_cache_project, "dockerhub-proxy") : "dockerhub-proxy"

  # ⚠️ 중요: Harbor token realm/redirect 및 내부 통신 안정화를 위해 기본적으로 DNS(hostname) 기반 hostport를 사용합니다.
  # - harbor_registry_hostport_by_dns: harbor.<base_domain>:80 형태
  # - RKE2 노드에 /etc/hosts를 자동으로 추가하여 내부망(Private IP)으로 해석되도록 합니다.
  harbor_registry_hostport = local.effective_use_harbor && length(data.terraform_remote_state.harbor) > 0 ? try(data.terraform_remote_state.harbor[0].outputs.harbor_registry_hostport_by_dns, null) : null

  # 00-network 기본 서브넷 tier는 public/db/k8s_cp/k8s_dp 입니다.
  control_plane_subnet_ids = try(local.subnet_ids_by_tier["k8s_cp"], [])
  worker_subnet_ids        = try(local.subnet_ids_by_tier["k8s_dp"], [])
  public_subnet_ids        = try(local.subnet_ids_by_tier["public"], [])
}

module "rke2" {
  source = "../../../modules/rke2-cluster"

  project = var.project
  env     = var.env
  name    = local.workload_name

  tags = local.common_tags

  vpc_id   = local.vpc_id
  vpc_cidr = local.vpc_cidr

  control_plane_subnet_ids = local.control_plane_subnet_ids
  worker_subnet_ids        = local.worker_subnet_ids

  control_plane_count = var.control_plane_count
  worker_count        = var.worker_count
  instance_type       = var.instance_type

  root_volume_size_gb = var.root_volume_size_gb
  root_volume_type    = var.root_volume_type

  enable_internal_nlb = var.enable_internal_nlb
  rke2_version        = var.rke2_version
  rke2_token          = var.rke2_token

  # 외부에서 주입된 추가 정책 ARN (Note: ExternalDNS 등은 별도 리소스로 부착됨)
  extra_policy_arns = var.extra_policy_arns

  # 10-security에서 정의된 정적 클라이언트 SG 주입 (Decoupling의 핵심)
  # - k8s_client: DB/Harbor 접근용 신원
  # - monitoring_client: Prometheus scraping 허용용 신원
  additional_security_group_ids = [
    try(data.terraform_remote_state.security.outputs.k8s_client_sg_id, ""),
    try(data.terraform_remote_state.security.outputs.monitoring_client_sg_id, "")
  ]

  ami_id    = var.ami_id  # Optional override
  os_family = var.os_family
  
  # Golden Image (handled by rke2-cluster -> ec2-instance)
  state_bucket     = var.state_bucket
  state_region     = var.state_region
  state_key_prefix = var.state_key_prefix

  # Harbor(내부 레지스트리) 연동 - 선택적
  harbor_registry_hostport          = local.harbor_registry_hostport
  harbor_hostname                   = local.harbor_hostname
  harbor_private_ip                 = local.harbor_private_ip
  harbor_add_hosts_entry            = true
  harbor_scheme                     = local.harbor_scheme
  harbor_proxy_project              = local.harbor_proxy_project
  disable_default_registry_fallback = local.effective_use_harbor ? var.disable_default_registry_fallback : false
  harbor_auth_enabled               = local.effective_use_harbor ? var.harbor_auth_enabled : false
  harbor_username                   = var.harbor_username
  harbor_password                   = var.harbor_password

  # Public Ingress NLB (Optional)
  enable_public_ingress_nlb           = var.enable_public_ingress_nlb
  enable_public_ingress_http_listener = var.enable_public_ingress_http_listener
  public_subnet_ids                   = local.public_subnet_ids
  ingress_http_nodeport               = var.ingress_http_nodeport
  ingress_https_nodeport              = var.ingress_https_nodeport

  # ACM TLS Termination (Optional)
  enable_acm_tls_termination = local.effective_enable_acm_tls_termination
  acm_certificate_arn        = local.effective_acm_certificate_arn
  acm_ssl_policy             = var.acm_ssl_policy

  # Cilium CNI (Phase 6: Network Evolution)
  cni                             = var.cni
  cilium_eni_mode                 = var.cilium_eni_mode
  cilium_enable_prefix_delegation = var.cilium_enable_prefix_delegation
  cilium_enable_hubble            = var.cilium_enable_hubble
  cilium_kube_proxy_replacement   = var.cilium_kube_proxy_replacement

  # CCM Removal (Phase 5/8: Cilium ENI에서 자연 해소)
  enable_aws_ccm                  = var.enable_aws_ccm
}

# ==============================================================================
# AWS Load Balancer Controller — IAM Policy
# Phase 1: Node IAM Role에 부착 (ExternalDNS와 동일 패턴)
# Phase 3: Keycloak OIDC 기반 IRSA로 분리 예정
# ==============================================================================

module "albc_iam" {
  source = "../../../modules/albc-iam"

  env     = var.env
  project = var.project

  cluster_name       = local.name
  vpc_id             = local.vpc_id
  node_iam_role_name = module.rke2.iam_role_name

  tags = local.common_tags
}
