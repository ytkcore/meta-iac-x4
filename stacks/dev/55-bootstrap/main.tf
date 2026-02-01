# ==============================================================================
# 55-bootstrap Stack
#
# Description:
#   - ArgoCD Helm Chart Deployment
#   - Pre-seeding Harbor OCI Registry with Helm Charts
#   - ArgoCD configuration (Ingress, Root App, OCI Secrets)
#
# Architecture:
#   - Controller: ArgoCD (Helm)
#   - Registry: Harbor OCI (Pre-seeded via script)
#   - Access: Ingress (NLB + ACM via ingress-nginx)
#
# Maintainer: DevOps Team
# ==============================================================================

locals {
  _backend_settings = {
    bucket     = var.state_bucket
    region     = var.state_region
    key_prefix = var.state_key_prefix
    azs        = var.azs
  }
}

# ------------------------------------------------------------------------------
# Remote State: RKE2 Cluster Info
# ------------------------------------------------------------------------------
data "terraform_remote_state" "rke2" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.state_region
    key    = "${var.state_key_prefix}/${var.env}/50-rke2.tfstate"
  }
}

# ------------------------------------------------------------------------------
# Remote State: Harbor (Optional)
# ------------------------------------------------------------------------------
data "aws_s3_objects" "harbor_tfstate" {
  bucket = var.state_bucket
  prefix = "${var.state_key_prefix}/${var.env}/45-harbor.tfstate"
}

locals {
  harbor_tfstate_exists = length(try(data.aws_s3_objects.harbor_tfstate.keys, [])) > 0
}

data "terraform_remote_state" "harbor" {
  count   = local.harbor_tfstate_exists ? 1 : 0
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.state_region
    key    = "${var.state_key_prefix}/${var.env}/45-harbor.tfstate"
  }
}

# Route53 Hosted Zone 자동 탐색 (ExternalDNS 등에서 참조)
data "aws_route53_zone" "selected" {
  count        = var.base_domain != "" ? 1 : 0
  name         = "${local.effective_base_domain}."
  private_zone = var.route53_private_zone
}

locals {
  # Harbor OCI 레지스트리 URL (remote state에서 자동 감지 또는 수동 지정)
  harbor_oci_url = var.harbor_oci_registry_url != "" ? var.harbor_oci_registry_url : (
    local.harbor_tfstate_exists ? try(data.terraform_remote_state.harbor[0].outputs.helm_oci_registry_url_by_dns, try(data.terraform_remote_state.harbor[0].outputs.helm_oci_registry_url, "")) : ""
  ) # Harbor OCI 사용 가능 여부
  harbor_oci_available = local.harbor_oci_url != "" && var.use_harbor_oci

  # Helm provider용 OCI URL (oci://<host>/<project>)
  harbor_oci_url_helm = local.harbor_oci_url

  # ArgoCD용: OCI registry host / repoURL은 oci:// prefix 없이 사용 (공식 문서 권장)
  # - repo secret url: <registry-host>
  # - application repoURL: <registry-host>/<project>
  harbor_oci_host        = local.harbor_oci_available ? element(split("/", replace(local.harbor_oci_url, "oci://", "")), 0) : ""
  harbor_oci_repo_argocd = local.harbor_oci_host != "" ? "${local.harbor_oci_host}/helm-charts" : ""

  # 실제 사용할 Helm 저장소 (Harbor OCI 또는 외부)
  argocd_repository = local.harbor_oci_available ? local.harbor_oci_url_helm : "https://argoproj.github.io/argo-helm"
  argocd_chart      = local.harbor_oci_available ? "argo-cd" : "argo-cd"

  # Rancher & CertManager locals removed (ArgoCD managed)
}

# ------------------------------------------------------------------------------
# Pre-seed Helm charts into Harbor OCI
# - Harbor EC2의 user_data seeding이 아직 완료되지 않았거나, 인터넷 단절 대비
# ------------------------------------------------------------------------------
resource "null_resource" "seed_missing_helm_charts" {

  triggers = {
    harbor_host    = local.harbor_oci_host
    argocd_version = var.argocd_version
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "${path.module}/../../../scripts/helm/seed-harbor.sh"

    environment = {
      HARBOR_HOST    = local.harbor_oci_host
      ADMIN_PASS     = var.harbor_admin_password
      PROJECT        = "helm-charts"
      ENABLE_SEED    = tostring(local.harbor_oci_available && var.auto_seed_missing_helm_charts)
      ARGOCD_VERSION = var.argocd_version
      # CertManager and Rancher will be managed by ArgoCD later
      CERT_MANAGER_VERSION = ""
      RANCHER_VERSION      = ""
    }
  }
}

# ------------------------------------------------------------------------------
# AWS Provider
# ------------------------------------------------------------------------------
provider "aws" {
  region = var.region
}

# ------------------------------------------------------------------------------
# Kubernetes & Helm Providers
# kubeconfig based connection (Bastion or Local)
# ------------------------------------------------------------------------------
provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = var.kubeconfig_context
  }

  # OCI 레지스트리 사용 시 실험적 기능 활성화
  experiments {
    manifest = true
  }
}

provider "kubectl" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context
}

# ------------------------------------------------------------------------------
# Local Variables
# ------------------------------------------------------------------------------
locals {
  effective_base_domain = var.base_domain != "" ? var.base_domain : var.domain
  argocd_hostname       = local.effective_base_domain != "" ? "${var.argocd_subdomain}.${local.effective_base_domain}" : ""
  rancher_hostname      = local.effective_base_domain != "" ? "rancher.${local.effective_base_domain}" : ""


  common_labels = {
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "bootstrap"
    "environment"                  = var.env
    "project"                      = var.project
  }
}

# ------------------------------------------------------------------------------
# 1. ArgoCD Installation
# ------------------------------------------------------------------------------



resource "helm_release" "argocd" {
  depends_on       = [null_resource.seed_missing_helm_charts]
  name             = "argocd"
  repository       = local.argocd_repository
  chart            = local.argocd_chart
  version          = var.argocd_version
  namespace        = var.argocd_namespace
  create_namespace = true

  # OCI 레지스트리 사용 시 인증 (Harbor HTTP)
  repository_username = local.harbor_oci_available ? "admin" : null
  repository_password = local.harbor_oci_available ? var.harbor_admin_password : null

  values = [
    templatefile("${path.module}/templates/argocd-values.yaml.tftpl", {
      argocd_hostname = local.argocd_hostname
      argocd_url      = local.argocd_hostname != "" ? "https://${local.argocd_hostname}" : ""

      server_replicas = var.argocd_ha_enabled ? 2 : var.argocd_server_replicas
      server_req_cpu  = var.argocd_resources.server.requests.cpu
      server_req_mem  = var.argocd_resources.server.requests.memory
      server_lim_cpu  = var.argocd_resources.server.limits.cpu
      server_lim_mem  = var.argocd_resources.server.limits.memory
      server_insecure = var.argocd_server_insecure

      service_type           = var.argocd_enable_ingress ? "ClusterIP" : "NodePort"
      service_nodeport_http  = var.argocd_enable_ingress ? "" : tostring(var.argocd_nodeport_http)
      service_nodeport_https = var.argocd_enable_ingress ? "" : tostring(var.argocd_nodeport_https)

      ingress_enabled    = var.argocd_enable_ingress
      ingress_class_name = var.argocd_ingress_class_name

      controller_replicas = var.argocd_ha_enabled ? 2 : 1
      controller_req_cpu  = var.argocd_resources.controller.requests.cpu
      controller_req_mem  = var.argocd_resources.controller.requests.memory
      controller_lim_cpu  = var.argocd_resources.controller.limits.cpu
      controller_lim_mem  = var.argocd_resources.controller.limits.memory

      repo_server_replicas = var.argocd_ha_enabled ? 2 : 1
      repo_server_req_cpu  = var.argocd_resources.repo_server.requests.cpu
      repo_server_req_mem  = var.argocd_resources.repo_server.requests.memory
      repo_server_lim_cpu  = var.argocd_resources.repo_server.limits.cpu
      repo_server_lim_mem  = var.argocd_resources.repo_server.limits.memory

      ha_enabled = var.argocd_ha_enabled
    })
  ]

  wait          = true
  wait_for_jobs = true
  timeout       = 600
}

# ------------------------------------------------------------------------------
# ArgoCD External Access via ingress-nginx (Public NLB + ACM TLS Termination)
# - NLB에서 TLS 종료 후 ingress-nginx(NodePort)로 HTTP 전달되는 구조 전제
# - Host 기반: https://argocd.<domain>
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Data Lookup: Ingress NLB (Recovery / Fallback)
# Remote state가 복구 중이거나 불완전할 경우, 실제 AWS 리소스를 직접 조회합니다.
# ------------------------------------------------------------------------------
# (Redundant block removed - moved to bottom)


# ------------------------------------------------------------------------------
# Route53 Alias Record: REMOVED
# - In Pure GitOps, Terraform cannot wait for the Ingress Controller (managed by ArgoCD)
#   to create the NLB and retrieve its hostname in the same `apply` run.
# - Recommendation: Use ExternalDNS or create DNS records manually after bootstrap.
# ------------------------------------------------------------------------------
/*
resource "aws_route53_record" "argocd" {
  count = var.enable_route53_argocd_alias && local.argocd_hostname != "" && local.can_create_dns_record ? 1 : 0

  zone_id = var.route53_zone_id != "" ? var.route53_zone_id : data.aws_route53_zone.selected[0].zone_id
  name    = local.argocd_hostname
  type    = "A"

  alias {
    name                   = local.final_nlb_dns
    zone_id                = local.final_nlb_zone_id
    evaluate_target_health = true
  }
}
*/

/*
resource "aws_route53_record" "rancher" {
  count = var.enable_route53_argocd_alias && local.rancher_hostname != "" && local.can_create_dns_record ? 1 : 0

  zone_id = var.route53_zone_id != "" ? var.route53_zone_id : data.aws_route53_zone.selected[0].zone_id
  name    = local.rancher_hostname
  type    = "A"

  alias {
    name                   = local.final_nlb_dns
    zone_id                = local.final_nlb_zone_id
    evaluate_target_health = true
  }
}
*/



# ------------------------------------------------------------------------------
# 3. ArgoCD Initial Admin Password
# ------------------------------------------------------------------------------
data "kubernetes_secret" "argocd_initial_admin" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = var.argocd_namespace
  }

  depends_on = [helm_release.argocd]
}


# ------------------------------------------------------------------------------
# ArgoCD Repository: Harbor OCI Helm Charts
# ------------------------------------------------------------------------------
resource "kubectl_manifest" "argocd_harbor_oci_repo" {
  count = local.harbor_oci_available ? 1 : 0

  yaml_body = templatefile("${path.module}/templates/harbor-oci-repo.yaml.tftpl", {
    name      = "harbor-oci-helm"
    namespace = var.argocd_namespace
    url       = local.harbor_oci_host
    password  = var.harbor_admin_password
  })

  depends_on = [
    helm_release.argocd
  ]
}

# ------------------------------------------------------------------------------
# 5. ArgoCD Repository Secret (Private Git Repo) - SSH Key Based
# ------------------------------------------------------------------------------
resource "kubernetes_secret" "argocd_repo_creds" {
  count = var.enable_gitops_apps && var.gitops_ssh_key_path != "" ? 1 : 0

  metadata {
    name      = "repo-creds"
    namespace = var.argocd_namespace
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type          = "git"
    url           = var.gitops_repo_url
    sshPrivateKey = file(pathexpand(var.gitops_ssh_key_path))
  }

  depends_on = [helm_release.argocd]
}

# ------------------------------------------------------------------------------
# 6. ArgoCD Root Application (App of Apps)
# ------------------------------------------------------------------------------
resource "kubectl_manifest" "argocd_root_app" {
  count = var.enable_gitops_apps ? 1 : 0

  yaml_body = templatefile("${path.module}/templates/argocd-root-app.yaml.tftpl", {
    namespace = var.argocd_namespace
    repo_url  = var.gitops_repo_url # Must be SSH URL (git@github.com:...)
    branch    = var.gitops_repo_branch
    path      = var.gitops_apps_path
  })

  depends_on = [
    helm_release.argocd,
    kubectl_manifest.argocd_harbor_oci_repo,
    kubernetes_secret.argocd_repo_creds
  ]
}
# ------------------------------------------------------------------------------
# Auto-discovery of ACM Certificate
# ------------------------------------------------------------------------------
locals {
  # ACM 자동 탐색을 위한 도메인 결정 (부트스트랩 단계에서 동적 할당)
  acm_search_domain = (
    var.base_domain != "" ? "*.${var.base_domain}" :
    var.domain != "" ? "*.${var.domain}" :
    null
  )
}

data "aws_acm_certificate" "wildcard" {
  # remote_state에서 ARN을 못 찾았을 때만 로컬 탐색 시도
  count = (
    try(data.terraform_remote_state.rke2.outputs.effective_acm_certificate_arn, null) == null &&
    local.acm_search_domain != null
  ) ? 1 : 0

  domain      = local.acm_search_domain
  statuses    = ["ISSUED"]
  most_recent = true
}

locals {
  # Final ACM ARN Resolution:
  # 1. 50-rke2 (Network/Var) - Primary source
  # 2. AWS Lookup (Discovery) - Secondary source
  final_acm_arn = coalesce(
    try(data.terraform_remote_state.rke2.outputs.effective_acm_certificate_arn, null),
    try(data.aws_acm_certificate.wildcard[0].arn, null),
    ""
  )
}

# ------------------------------------------------------------------------------
# 7. ArgoCD Core Add-ons: NGINX Ingress Controller
# - Put the manifest in GitOps repository for synchronization
# ------------------------------------------------------------------------------
# 7. Infrastructure Context for GitOps (Day 2 Operations)
# - Stores dynamic infrastructure values in a Secret (Security Best Practice).
# - Future GitOps workflows (Helm Lookup, Kyverno) can consume this.
# ------------------------------------------------------------------------------
resource "kubernetes_secret" "infra_context" {
  metadata {
    name      = "infra-context"
    namespace = "kube-system" # Globally accessible location
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "component"                    = "infra-context"
    }
  }

  data = {
    base_domain         = local.effective_base_domain
    acm_certificate_arn = local.final_acm_arn
    vpc_id              = try(data.terraform_remote_state.rke2.outputs.vpc_id, "")
    environment         = var.env
    project             = var.project
    region              = var.region
    # ExternalDNS 등에서 사용할 Zone ID 주입
    route53_zone_id = var.route53_zone_id != "" ? var.route53_zone_id : try(data.aws_route53_zone.selected[0].zone_id, "")
  }

  type = "Opaque"
}

# ------------------------------------------------------------------------------
# 8. ArgoCD Core Add-ons: Direct Apply (Disabled for Pure GitOps)
# - Moved to Git Repository (GitOps).
# - Terraform only bootstraps ArgoCD, Repository Secret, and Root App.
# ------------------------------------------------------------------------------

/*
locals {
  # Helm Chart Repositories (Public vs Harbor OCI)
  # If Harbor OCI is available, pointing to "harbor.domain/helm-charts"
  # Note: ArgoCD expects OCI repoURL without `oci://` prefix if it's treated as Helm repo,
  # BUT for OCI registries, standard is `registry/project`.
  # We use `local.harbor_oci_repo_argocd` which was defined at line 81.
  
  # Cert Manager
  cert_manager_repo    = local.harbor_oci_available ? local.harbor_oci_repo_argocd : "https://charts.jetstack.io"
  cert_manager_version = "v1.13.3"
  
  # Nginx Ingress
  nginx_ingress_repo    = local.harbor_oci_available ? local.harbor_oci_repo_argocd : "https://kubernetes.github.io/ingress-nginx"
  nginx_ingress_version = "4.11.3"

  # Rancher
  rancher_repo    = local.harbor_oci_available ? local.harbor_oci_repo_argocd : "https://releases.rancher.com/server-charts/stable"
  rancher_version = "2.13.2"
}

resource "kubectl_manifest" "argocd_app_cert_manager" {
  count = var.argocd_enable_ingress ? 1 : 0

  yaml_body = templatefile("${path.module}/templates/cert-manager.yaml.tftpl", {
    argocd_namespace = var.argocd_namespace
    repo_url         = local.cert_manager_repo
    target_revision  = local.cert_manager_version
  })

  depends_on = [helm_release.argocd]
}

resource "kubectl_manifest" "argocd_app_nginx_ingress" {
  count = var.argocd_enable_ingress ? 1 : 0

  yaml_body = templatefile("${path.module}/templates/nginx-ingress.yaml.tftpl", {
    namespace       = var.argocd_namespace
    acm_arn         = local.final_acm_arn
    repo_url        = local.nginx_ingress_repo
    target_revision = local.nginx_ingress_version
  })

  depends_on = [helm_release.argocd, kubectl_manifest.argocd_app_cert_manager]
}

resource "kubectl_manifest" "argocd_app_rancher" {
  count = var.argocd_enable_ingress ? 1 : 0

  yaml_body = templatefile("${path.module}/templates/rancher.yaml.tftpl", {
    argocd_namespace = var.argocd_namespace
    rancher_hostname = local.rancher_hostname
    repo_url         = local.rancher_repo
    target_revision  = local.rancher_version
  })

  depends_on = [helm_release.argocd, kubectl_manifest.argocd_app_nginx_ingress] # Wave 2
}
*/

# ------------------------------------------------------------------------------
# Ingress Service Lookup (for Route53 Alias)
# ------------------------------------------------------------------------------
# Note: The service uses `depends_on` to wait for Helm release, but typically
# the LoadBalancer is provisioned asynchronously.
# On the FIRST apply, this might fail or return empty if not careful.
# We CANNOT force Terraform to wait for the LB to be provisioned during `apply`.
# The standard solution is to separate `apply` into two stages or use a specialized
# wait script/resource.
# However, to support a single `make apply` logic, we will attempt to look it up
# only if we think it exists, or just accept that DNS update requires a second apply.
#
# ------------------------------------------------------------------------------
# Ingress Service Lookup: REMOVED
# - Causes "Invalid count argument" error because `depends_on` makes the result
#   unknown at plan time.
# ------------------------------------------------------------------------------
/*
data "kubernetes_service" "ingress_nginx" {
  count = var.argocd_enable_ingress ? 1 : 0
  metadata {
    name      = "nginx-ingress-controller"
    namespace = "ingress-nginx"
  }
  depends_on = [helm_release.argocd]
}
*/

locals {
  # Service Managed NLB DNS (Dynamic)
  # - Disabled service lookup to fix Plan error.
  service_nlb_dns = null


  remote_nlb_dns     = try(data.terraform_remote_state.rke2.outputs.ingress_public_nlb_dns, null)
  remote_nlb_zone_id = try(data.terraform_remote_state.rke2.outputs.ingress_public_nlb_zone_id, null)

  # NLB Name lookup (Fallback)
  target_nlb_name = substr("${var.env}-${var.project}-k8s-nlb-ingress", 0, 32)
}

# AWS LB Data Source Removed
# We rely on `kubernetes_service` (post-apply) or `remote_state` (pre-existing)
# The Zone ID is handled via static mapping or remote state.

locals {
  _nlb_dns_candidates = compact([
    local.service_nlb_dns,
    local.remote_nlb_dns
  ])
  final_nlb_dns = length(local._nlb_dns_candidates) > 0 ? local._nlb_dns_candidates[0] : ""

  _nlb_zone_candidates = compact([
    local.service_nlb_dns != null ? "ZWK97P98S7624" : null, # Fixed AZ for APN2 if service DNS exists
    local.remote_nlb_zone_id
  ])
  final_nlb_zone_id = length(local._nlb_zone_candidates) > 0 ? local._nlb_zone_candidates[0] : ""

  can_create_dns_record = local.final_nlb_dns != ""
}
