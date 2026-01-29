# =============================================================================
# Harbor Stack - ALB + HTTPS + Helm Seeding
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Remote State
# -----------------------------------------------------------------------------
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
# 2. Data Sources
# -----------------------------------------------------------------------------

# Public Subnets (ALB용 - AZ당 1개)
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.terraform_remote_state.network.outputs.vpc_id]
  }
  filter {
    name   = "tag:Name"
    values = ["*public*"]
  }
}

data "aws_subnet" "details" {
  for_each = toset(data.aws_subnets.public.ids)
  id       = each.value
}

# ACM 인증서 자동 탐색 (*.base_domain)
data "aws_acm_certificate" "wildcard" {
  count       = var.alb_certificate_arn == "" ? 1 : 0
  domain      = "*.${var.base_domain}"
  statuses    = ["ISSUED"]
  most_recent = true
}

# Route53 Hosted Zone 자동 탐색
data "aws_route53_zone" "selected" {
  count        = var.enable_route53_harbor_cname && var.route53_zone_id == "" ? 1 : 0
  name         = "${var.base_domain}."
  private_zone = var.route53_private_zone
}

# -----------------------------------------------------------------------------
# 3. Locals (통합)
# -----------------------------------------------------------------------------
locals {
  # [NEW] Generate name and tags locally
  workload_name = "harbor"
  name          = "${var.project}-${var.env}-${local.workload_name}"
  tags = {
    ManagedBy   = "terraform"
    Project     = var.project
    Environment = var.env
  }

  # Network
  vpc_id    = data.terraform_remote_state.network.outputs.vpc_id
  subnet_id = data.terraform_remote_state.network.outputs.subnet_ids[var.harbor_subnet_key]

  # ALB Subnets (AZ당 1개만 선택)
  subnets_by_az     = { for s in data.aws_subnet.details : s.availability_zone => s.id }
  final_alb_subnets = values(local.subnets_by_az)

  # Harbor hostname
  final_hostname = "harbor.${var.base_domain}"

  # ACM (명시적 ARN 우선, 없으면 자동 탐색)
  acm_certificate_arn = var.alb_certificate_arn != "" ? var.alb_certificate_arn : try(data.aws_acm_certificate.wildcard[0].arn, null)

  # Route53 (명시적 zone_id 우선, 없으면 자동 탐색)
  route53_zone_id     = var.route53_zone_id != "" ? var.route53_zone_id : try(data.aws_route53_zone.selected[0].zone_id, "")
  harbor_alb_dns_name = try(module.harbor.alb_dns_name, "")
}

# -----------------------------------------------------------------------------
# 4. Harbor Module
# -----------------------------------------------------------------------------
module "harbor" {
  source = "../../../modules/harbor-ec2"

  # Basic
  name    = local.workload_name
  env     = var.env
  project = var.project
  region  = var.region

  # Network
  vpc_id    = local.vpc_id
  subnet_id = local.subnet_id

  # EC2
  instance_type    = var.instance_type
  key_name         = var.key_name
  root_volume_size = var.root_volume_size

  # Harbor App
  harbor_hostname = local.final_hostname
  enable_tls      = var.harbor_enable_tls
  admin_password  = var.admin_password
  db_password     = var.db_password

  # Storage
  storage_type       = var.storage_type
  target_bucket_name = var.target_bucket_name
  create_bucket      = var.create_bucket

  # Proxy Cache
  proxy_cache_project = var.harbor_proxy_cache_project
  create_proxy_cache  = var.create_proxy_cache

  # Image Seeding
  seed_images       = var.seed_images
  seed_postgres_tag = var.seed_postgres_tag
  seed_neo4j_tag    = var.seed_neo4j_tag

  # Helm Seeding (user-data mode)
  seed_helm_charts          = var.helm_seeding_mode == "user-data"
  argocd_chart_version      = var.argocd_chart_version
  certmanager_chart_version = var.certmanager_chart_version
  rancher_chart_version     = var.rancher_chart_version

  # ALB
  enable_alb          = true
  alb_subnet_ids      = local.final_alb_subnets
  alb_certificate_arn = local.acm_certificate_arn
  alb_internal        = false
  alb_ingress_cidrs   = ["0.0.0.0/0"]
}

# -----------------------------------------------------------------------------
# 5. Route53 CNAME
# -----------------------------------------------------------------------------
resource "aws_route53_record" "harbor_cname" {
  count           = var.enable_route53_harbor_cname && var.enable_alb && local.route53_zone_id != "" ? 1 : 0
  allow_overwrite = true

  zone_id = local.route53_zone_id
  name    = local.final_hostname
  type    = "CNAME"
  ttl     = 300
  records = [local.harbor_alb_dns_name]
}

# -----------------------------------------------------------------------------
# 6. Helm Chart Seeding (local-exec)
# -----------------------------------------------------------------------------
resource "null_resource" "seed_helm_charts" {
  count = var.helm_seeding_mode == "local-exec" ? 1 : 0

  triggers = {
    harbor_instance = module.harbor.instance_id
    chart_versions  = "${var.argocd_chart_version}-${var.certmanager_chart_version}-${var.rancher_chart_version}"
  }

  depends_on = [module.harbor, aws_route53_record.harbor_cname]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    working_dir = path.root
    command     = <<-EOT
      set -e
      LOG="/tmp/harbor-seeding.log"
      exec > >(tee -a "$LOG") 2>&1
      echo "=== Helm Seeding Started: $(date) ==="

      ALB_DNS="${module.harbor.alb_dns_name}"
      HARBOR_CNAME="${local.final_hostname}"
      SCHEME="${local.acm_certificate_arn != null ? "https" : "http"}"

      echo "ALB: $ALB_DNS | CNAME: $HARBOR_CNAME | Scheme: $SCHEME"

      # Smart wait: 즉시 체크 → 실패 시 대기 후 재시도
      if curl -fsSk --connect-timeout 5 "$SCHEME://$ALB_DNS/api/v2.0/health" 2>/dev/null | grep -q healthy; then
        echo "Harbor already healthy!"
      else
        echo "Waiting 120s for EC2 bootstrap..."
        sleep 120
        for i in $(seq 1 60); do
          curl -fsSk --connect-timeout 5 "$SCHEME://$ALB_DNS/api/v2.0/health" 2>/dev/null | grep -q healthy && break
          echo "Waiting... ($i/60)"
          sleep 10
        done
      fi

      # DNS 전파 확인
      DNS_OK=false
      for i in $(seq 1 12); do
        host "$HARBOR_CNAME" 2>/dev/null | grep -q "alias\|address" && DNS_OK=true && break
        echo "DNS propagation... ($i/12)"
        sleep 10
      done

      # Seeding
      if [ "$DNS_OK" = "true" ]; then
        ../../../scripts/harbor/seed-helm-charts-client.sh "$HARBOR_CNAME" "${var.admin_password}" \
          --argocd-version "${var.argocd_chart_version}" \
          --certmanager-version "${var.certmanager_chart_version}" \
          --rancher-version "${var.rancher_chart_version}"
      else
        echo "DNS not ready, using ALB with --insecure"
        ../../../scripts/harbor/seed-helm-charts-client.sh "$ALB_DNS" "${var.admin_password}" \
          --argocd-version "${var.argocd_chart_version}" \
          --certmanager-version "${var.certmanager_chart_version}" \
          --rancher-version "${var.rancher_chart_version}" \
          --insecure
      fi

      echo "=== Helm Seeding Completed: $(date) ==="
    EOT
  }
}
