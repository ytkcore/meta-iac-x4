# -----------------------------------------------------------------------------
# 1. Backend & Network State
# -----------------------------------------------------------------------------
locals {
  _backend_settings = {
    bucket     = var.state_bucket
    region     = var.state_region
    key_prefix = var.state_key_prefix
  }
}

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket  = var.state_bucket
    region  = var.state_region
    key     = "${var.state_key_prefix}/${var.env}/00-network.tfstate"
    encrypt = true
  }
}

# -----------------------------------------------------------------------------
# 2. 자동 계산 로직 (Locals)
# -----------------------------------------------------------------------------
locals {
  vpc_id    = data.terraform_remote_state.network.outputs.vpc_id
  subnet_id = data.terraform_remote_state.network.outputs.subnet_ids[var.harbor_subnet_key]

  # [핵심] 입력받은 루트 도메인 앞에 'harbor'를 자동으로 붙임
  final_hostname = "harbor.${var.base_domain}"

  # [핵심] 인증서 검색용 도메인 (*.mymeta.net)
  cert_search_domain = "*.${var.base_domain}"
}

# -----------------------------------------------------------------------------
# 3. 리소스 자동 검색 및 필터링 (ALB 에러 해결)
# -----------------------------------------------------------------------------

# 1) VPC 내의 후보 서브넷(Public)들을 일단 모두 가져옵니다.
data "aws_subnets" "candidates" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }

  # [중요] Public Subnet만 가져오기 위해 이름에 "public"이 들어간 것을 찾습니다.
  # 만약 태그 규칙이 다르다면 이 부분을 조정하거나 주석 처리하세요.
  filter {
    name   = "tag:Name"
    values = ["*public*"]
  }
}

# 2) 가져온 서브넷 ID 각각의 상세 정보(어느 AZ인지)를 조회합니다.
data "aws_subnet" "details" {
  for_each = toset(data.aws_subnets.candidates.ids)
  id       = each.value
}

# 3) [핵심] AZ별로 하나의 서브넷만 남깁니다.
locals {
  # 맵(Map)을 만들면 Key(AZ 이름)가 중복될 경우 뒤의 값으로 덮어씌워지는 특성을 이용합니다.
  # 예: { "ap-northeast-2a" = "subnet-1", "ap-northeast-2a" = "subnet-2" } -> 결과적으로 하나만 남음
  subnets_by_az = {
    for s in data.aws_subnet.details : s.availability_zone => s.id
  }

  # 맵에서 서브넷 ID들만 추출 (이제 AZ당 1개임이 보장됨)
  final_alb_subnets = values(local.subnets_by_az)
}

# ACM certificate lookup removed: provide alb_certificate_arn explicitly when needed.

# -----------------------------------------------------------------------------
# 4. Harbor 모듈 호출
# -----------------------------------------------------------------------------
module "harbor" {
  source = "../../../modules/harbor-ec2"

  # ... (기존 설정들: Basic, Infra, App, Storage 등 그대로 유지) ...
  name   = var.name
  env    = var.env
  region = var.region

  vpc_id           = local.vpc_id
  subnet_id        = local.subnet_id
  instance_type    = var.instance_type
  key_name         = var.key_name
  root_volume_size = var.root_volume_size

  harbor_hostname = local.final_hostname
  enable_tls      = var.harbor_enable_tls
  admin_password  = var.admin_password
  db_password     = var.db_password

  storage_type        = var.storage_type
  target_bucket_name  = var.target_bucket_name
  create_bucket       = var.create_bucket
  proxy_cache_project = var.harbor_proxy_cache_project
  create_proxy_cache  = var.create_proxy_cache
  seed_images         = var.seed_images
  seed_postgres_tag   = var.seed_postgres_tag
  seed_neo4j_tag      = var.seed_neo4j_tag

  # Helm chart seeding (OCI)
  seed_helm_charts          = var.seed_helm_charts
  argocd_chart_version      = var.argocd_chart_version
  certmanager_chart_version = var.certmanager_chart_version
  rancher_chart_version     = var.rancher_chart_version

  # [수정] 위에서 필터링한 "AZ당 1개" 리스트를 주입
  enable_alb     = true
  alb_subnet_ids = local.final_alb_subnets

  alb_certificate_arn = (var.alb_certificate_arn != "" ? var.alb_certificate_arn : null)
  alb_internal        = false
  alb_ingress_cidrs   = ["0.0.0.0/0"]
}

# -----------------------------------------------------------------------------
# 5. Route53: harbor.<base_domain> CNAME -> Harbor ALB DNS (optional)
# -----------------------------------------------------------------------------

# Hosted Zone auto-discovery removed to avoid hard-fail when no zone exists.
# Provide route53_zone_id explicitly when enable_route53_harbor_cname=true.

locals {
  route53_zone_id_effective = var.route53_zone_id
  harbor_alb_dns_name       = try(module.harbor.alb_dns_name, "")
}

resource "aws_route53_record" "harbor_cname" {
  allow_overwrite = true
  count           = var.enable_route53_harbor_cname && var.enable_alb && local.route53_zone_id_effective != "" ? 1 : 0
  zone_id         = local.route53_zone_id_effective
  name            = local.final_hostname
  type            = "CNAME"
  ttl             = 300
  records         = [local.harbor_alb_dns_name]
}

resource "null_resource" "save_domain_setting" {
  triggers = {
    domain = var.base_domain
  }

  provisioner "local-exec" {
    # domain.auto.tfvars 라는 별도 파일에 저장하여 기존 설정 파일과 충돌 방지
    command = "echo 'base_domain = \"${var.base_domain}\"' > domain.auto.tfvars"
  }
}
