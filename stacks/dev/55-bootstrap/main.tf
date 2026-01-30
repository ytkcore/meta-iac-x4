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

# Route53 Hosted Zone 자동 탐색
data "aws_route53_zone" "selected" {
  count        = var.enable_route53_argocd_alias && var.route53_zone_id == "" ? 1 : 0
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

  # Global settings
  set {
    name  = "global.domain"
    value = local.argocd_hostname
  }

  # UI/Redirect URL (NLB+ACM TLS 종료 전제)
  dynamic "set" {
    for_each = local.argocd_hostname != "" ? [1] : []
    content {
      name  = "configs.cm.url"
      value = "https://${local.argocd_hostname}"
    }
  }

  # Server configuration
  set {
    name  = "server.replicas"
    value = var.argocd_ha_enabled ? "2" : tostring(var.argocd_server_replicas)
  }

  # Service exposure mode
  dynamic "set" {
    for_each = var.argocd_enable_ingress ? [1] : []
    content {
      name  = "server.service.type"
      value = "ClusterIP"
    }
  }

  dynamic "set" {
    for_each = var.argocd_enable_ingress ? [1] : []
    content {
      name  = "server.ingress.enabled"
      value = "true"
    }
  }

  dynamic "set" {
    for_each = var.argocd_enable_ingress && local.argocd_hostname != "" ? [1] : []
    content {
      name  = "server.ingress.ingressClassName"
      value = var.argocd_ingress_class_name
    }
  }

  dynamic "set" {
    for_each = var.argocd_enable_ingress && local.argocd_hostname != "" ? [1] : []
    content {
      name  = "server.ingress.hosts[0]"
      value = local.argocd_hostname
    }
  }

  # External TLS termination (NLB+ACM): disable SSL redirect and pass https headers to upstream
  dynamic "set" {
    for_each = var.argocd_enable_ingress ? [1] : []
    content {
      name  = "server.ingress.annotations.nginx.ingress.kubernetes.io/ssl-redirect"
      value = "false"
    }
  }

  dynamic "set" {
    for_each = var.argocd_enable_ingress ? [1] : []
    content {
      name  = "server.ingress.annotations.nginx.ingress.kubernetes.io/force-ssl-redirect"
      value = "false"
    }
  }

  dynamic "set" {
    for_each = var.argocd_enable_ingress ? [1] : []
    content {
      name  = "server.ingress.annotations.nginx.ingress.kubernetes.io/backend-protocol"
      value = "HTTP"
    }
  }

  dynamic "set" {
    for_each = var.argocd_enable_ingress ? [1] : []
    content {
      name  = "server.ingress.annotations.nginx.ingress.kubernetes.io/proxy-buffer-size"
      value = "16k"
    }
  }

  dynamic "set" {
    for_each = var.argocd_enable_ingress ? [1] : []
    content {
      name  = "server.ingress.annotations.nginx.ingress.kubernetes.io/proxy-body-size"
      value = "0"
    }
  }

  # If Ingress is disabled, expose NodePort directly (optional)
  dynamic "set" {
    for_each = var.argocd_enable_ingress ? [] : [1]
    content {
      name  = "server.service.type"
      value = "NodePort"
    }
  }

  dynamic "set" {
    for_each = var.argocd_enable_ingress ? [] : [1]
    content {
      name  = "server.service.nodePortHttp"
      value = tostring(var.argocd_nodeport_http)
    }
  }

  dynamic "set" {
    for_each = var.argocd_enable_ingress ? [] : [1]
    content {
      name  = "server.service.nodePortHttps"
      value = tostring(var.argocd_nodeport_https)
    }
  }
  # Insecure mode (for external TLS termination at NLB)
  dynamic "set" {
    for_each = var.argocd_server_insecure ? [1] : []
    content {
      name  = "server.extraArgs[0]"
      value = "--insecure"
    }
  }

  # Server Resources
  set {
    name  = "server.resources.requests.cpu"
    value = var.argocd_resources.server.requests.cpu
  }

  set {
    name  = "server.resources.requests.memory"
    value = var.argocd_resources.server.requests.memory
  }

  set {
    name  = "server.resources.limits.cpu"
    value = var.argocd_resources.server.limits.cpu
  }

  set {
    name  = "server.resources.limits.memory"
    value = var.argocd_resources.server.limits.memory
  }

  # Controller configuration (HA)
  set {
    name  = "controller.replicas"
    value = var.argocd_ha_enabled ? "2" : "1"
  }

  set {
    name  = "controller.resources.requests.cpu"
    value = var.argocd_resources.controller.requests.cpu
  }

  set {
    name  = "controller.resources.requests.memory"
    value = var.argocd_resources.controller.requests.memory
  }

  set {
    name  = "controller.resources.limits.cpu"
    value = var.argocd_resources.controller.limits.cpu
  }

  set {
    name  = "controller.resources.limits.memory"
    value = var.argocd_resources.controller.limits.memory
  }

  # Repo Server configuration (HA)
  set {
    name  = "repoServer.replicas"
    value = var.argocd_ha_enabled ? "2" : "1"
  }

  set {
    name  = "repoServer.resources.requests.cpu"
    value = var.argocd_resources.repo_server.requests.cpu
  }

  set {
    name  = "repoServer.resources.requests.memory"
    value = var.argocd_resources.repo_server.requests.memory
  }

  set {
    name  = "repoServer.resources.limits.cpu"
    value = var.argocd_resources.repo_server.limits.cpu
  }

  set {
    name  = "repoServer.resources.limits.memory"
    value = var.argocd_resources.repo_server.limits.memory
  }

  # Redis HA (for HA mode)
  set {
    name  = "redis-ha.enabled"
    value = var.argocd_ha_enabled ? "true" : "false"
  }

  set {
    name  = "redis.enabled"
    value = var.argocd_ha_enabled ? "false" : "true"
  }

  # Dex (SSO) - disabled by default
  set {
    name  = "dex.enabled"
    value = "false"
  }

  # Notifications - disabled by default
  set {
    name  = "notifications.enabled"
    value = "false"
  }

  # ApplicationSet - enabled
  set {
    name  = "applicationSet.enabled"
    value = "true"
  }

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
# Route53 Alias Record for ArgoCD
# ------------------------------------------------------------------------------
resource "aws_route53_record" "argocd" {
  count = var.enable_route53_argocd_alias && local.argocd_hostname != "" ? 1 : 0

  zone_id = var.route53_zone_id != "" ? var.route53_zone_id : data.aws_route53_zone.selected[0].zone_id
  name    = local.argocd_hostname
  type    = "A"

  alias {
    name                   = data.terraform_remote_state.rke2.outputs.ingress_public_nlb_dns
    zone_id                = data.terraform_remote_state.rke2.outputs.ingress_public_nlb_zone_id
    evaluate_target_health = true
  }
}

# ------------------------------------------------------------------------------
# Route53 Alias Record for Rancher
# ------------------------------------------------------------------------------
resource "aws_route53_record" "rancher" {
  count = var.enable_route53_argocd_alias && local.rancher_hostname != "" ? 1 : 0

  zone_id = var.route53_zone_id != "" ? var.route53_zone_id : data.aws_route53_zone.selected[0].zone_id
  name    = local.rancher_hostname
  type    = "A"

  alias {
    name                   = data.terraform_remote_state.rke2.outputs.ingress_public_nlb_dns
    zone_id                = data.terraform_remote_state.rke2.outputs.ingress_public_nlb_zone_id
    evaluate_target_health = true
  }
}



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
