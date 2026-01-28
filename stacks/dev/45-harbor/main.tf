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

# -----------------------------------------------------------------------------
# ACM 인증서 자동 탐색 (*.base_domain 와일드카드 인증서)
# -----------------------------------------------------------------------------
data "aws_acm_certificate" "wildcard" {
  count       = var.alb_certificate_arn == "" ? 1 : 0
  domain      = "*.${var.base_domain}"
  statuses    = ["ISSUED"]
  most_recent = true
}

locals {
  # 명시적으로 제공된 ARN이 있으면 사용, 없으면 자동 탐색
  acm_certificate_arn = var.alb_certificate_arn != "" ? var.alb_certificate_arn : try(data.aws_acm_certificate.wildcard[0].arn, null)
}

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

  # Helm chart seeding (OCI) - user-data 모드일 때만 활성화
  seed_helm_charts          = var.helm_seeding_mode == "user-data"
  argocd_chart_version      = var.argocd_chart_version
  certmanager_chart_version = var.certmanager_chart_version
  rancher_chart_version     = var.rancher_chart_version

  # [수정] 위에서 필터링한 "AZ당 1개" 리스트를 주입
  enable_alb     = true
  alb_subnet_ids = local.final_alb_subnets

  alb_certificate_arn = local.acm_certificate_arn
  alb_internal        = false
  alb_ingress_cidrs   = ["0.0.0.0/0"]
}

# -----------------------------------------------------------------------------
# 5. Route53: harbor.<base_domain> CNAME -> Harbor ALB DNS (optional)
# -----------------------------------------------------------------------------

# Route53 Hosted Zone 동적 탐색 (존재하지 않으면 null 반환)
data "aws_route53_zone" "selected" {
  count        = var.enable_route53_harbor_cname && var.route53_zone_id == "" ? 1 : 0
  name         = "${var.base_domain}."
  private_zone = var.route53_private_zone
}

locals {
  # route53_zone_id가 명시적으로 제공되면 사용, 아니면 동적 탐색 결과 사용
  route53_zone_id_effective = var.route53_zone_id != "" ? var.route53_zone_id : try(data.aws_route53_zone.selected[0].zone_id, "")
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

# -----------------------------------------------------------------------------
# 6. Helm Chart Seeding (Local-Exec 방식)
# -----------------------------------------------------------------------------
# user_data 대신 로컬에서 직접 Harbor API로 차트를 시딩합니다.
# 테스트 완료 후 user_data로 다시 반영할 수 있습니다.

resource "null_resource" "seed_helm_charts" {
  count = var.helm_seeding_mode == "local-exec" ? 1 : 0

  triggers = {
    harbor_instance = module.harbor.instance_id
    argocd_version  = var.argocd_chart_version
    certmanager_ver = var.certmanager_chart_version
    rancher_version = var.rancher_chart_version
  }

  # Route53 CNAME 생성 후 실행 (DNS 전파 대기)
  depends_on = [module.harbor, aws_route53_record.harbor_cname]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    working_dir = path.root
    command     = <<-EOT
      set -e
      
      # 로그 파일 설정 (모니터링: tail -f /tmp/harbor-seeding.log)
      LOG_FILE="/tmp/harbor-seeding.log"
      echo "=== Helm Seeding Started: $(date) ===" | tee -a "$LOG_FILE"
      exec > >(tee -a "$LOG_FILE") 2>&1
      
      # ALB DNS (health check용)
      ALB_DNS="${module.harbor.alb_dns_name}"
      # CNAME (seeding용 - ACM 인증서와 일치)
      HARBOR_CNAME="${local.final_hostname}"
      SCHEME="${local.acm_certificate_arn != null ? "https" : "http"}"
      
      echo "ALB DNS: $ALB_DNS"
      echo "Harbor CNAME: $HARBOR_CNAME"
      echo "Scheme: $SCHEME"
      
      # Smart wait: 먼저 health check 시도, 실패하면 대기 후 재시도
      echo "Checking if Harbor is already running..."
      HARBOR_READY=false
      
      # 1차: 즉시 체크 (기존 EC2인 경우 바로 성공)
      if curl -fsSk --connect-timeout 5 "$SCHEME://$ALB_DNS/api/v2.0/health" 2>/dev/null | grep -q healthy; then
        echo "Harbor is already healthy! Skipping wait."
        HARBOR_READY=true
      else
        # 신규 배포: 120초 대기 후 재시도
        echo "Harbor not ready. Waiting 120 seconds for EC2 bootstrap..."
        sleep 120
        
        # 2차: 최대 60회 × 10초 = 10분 대기
        echo "Checking Harbor health via ALB..."
        for i in $(seq 1 60); do
          if curl -fsSk --connect-timeout 5 "$SCHEME://$ALB_DNS/api/v2.0/health" 2>/dev/null | grep -q healthy; then
            echo "Harbor is healthy!"
            HARBOR_READY=true
            break
          fi
          echo "Waiting for Harbor... (attempt $i/60)"
          sleep 10
        done
      fi
      
      if [ "$HARBOR_READY" != "true" ]; then
        echo "ERROR: Harbor did not become healthy in time"
        exit 1
      fi
      
      # DNS 전파 확인 (CNAME이 ALB로 해석되는지 체크)
      echo "Checking DNS propagation for $HARBOR_CNAME..."
      DNS_READY=false
      for i in $(seq 1 12); do
        if host "$HARBOR_CNAME" 2>/dev/null | grep -q "alias\|address"; then
          echo "DNS is ready!"
          DNS_READY=true
          break
        fi
        echo "Waiting for DNS propagation... (attempt $i/12)"
        sleep 10
      done
      
      echo "=== Starting Helm chart seeding ==="
      if [ "$DNS_READY" = "true" ]; then
        # CNAME 사용 (인증서와 일치)
        ../../../scripts/seed-helm-charts.sh \
          "$HARBOR_CNAME" \
          "${var.admin_password}" \
          --argocd-version "${var.argocd_chart_version}" \
          --certmanager-version "${var.certmanager_chart_version}" \
          --rancher-version "${var.rancher_chart_version}"
      else
        # DNS 미전파 시 ALB DNS + insecure 모드
        echo "DNS not ready, using ALB DNS with --insecure"
        ../../../scripts/seed-helm-charts.sh \
          "$ALB_DNS" \
          "${var.admin_password}" \
          --argocd-version "${var.argocd_chart_version}" \
          --certmanager-version "${var.certmanager_chart_version}" \
          --rancher-version "${var.rancher_chart_version}" \
          --insecure
      fi
      
      echo "=== Helm Seeding Completed: $(date) ==="
    EOT
  }
}
