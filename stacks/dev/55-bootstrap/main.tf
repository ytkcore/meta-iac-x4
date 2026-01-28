################################################################################
# 55-bootstrap: ArgoCD + cert-manager 설치 (Terraform Helm Provider)
#
# DevSecOps Best Practice:
# - Infrastructure Bootstrap은 Terraform으로 코드화
# - Day-2 Operations는 ArgoCD GitOps로 위임
#
# 배포 순서:
# 1. cert-manager (선택적)
# 2. ArgoCD
# 3. ArgoCD Root Application (App-of-Apps, 선택적)
#
# Harbor OCI 지원:
# - use_harbor_oci = true (기본값): Harbor OCI 레지스트리에서 Helm 차트 설치
# - use_harbor_oci = false: 외부 Helm 저장소 직접 사용
################################################################################

locals {
  _backend_settings = {
    bucket     = var.state_bucket
    region     = var.state_region
    key_prefix = var.state_key_prefix
    azs        = var.azs
  }
}

# -----------------------------------------------------------------------------
# Remote State (RKE2 클러스터 정보)
# -----------------------------------------------------------------------------
data "terraform_remote_state" "rke2" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.state_region
    key    = "${var.state_key_prefix}/${var.env}/50-rke2.tfstate"
  }
}

# -----------------------------------------------------------------------------
# Remote State (Harbor - Optional)
# -----------------------------------------------------------------------------
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

locals {
  # Harbor OCI 레지스트리 URL (remote state에서 자동 감지 또는 수동 지정)
  harbor_oci_url = var.harbor_oci_registry_url != "" ? var.harbor_oci_registry_url : (
    local.harbor_tfstate_exists ? try(data.terraform_remote_state.harbor[0].outputs.helm_oci_registry_url_by_dns, try(data.terraform_remote_state.harbor[0].outputs.helm_oci_registry_url, "")) : ""
  )# Harbor OCI 사용 가능 여부
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
  
  certmanager_repository = local.harbor_oci_available ? local.harbor_oci_url_helm : "https://charts.jetstack.io"
  certmanager_chart      = local.harbor_oci_available ? "cert-manager" : "cert-manager"


  # Rancher 소스 결정 (내부 완결: Harbor OCI 또는 내부 Git)
  # Rancher App(ArgoCD) 기준 repoURL:
  # - OCI(내부 완결): <harbor-host>/helm-charts (oci:// prefix 없이)
  # - External: https://releases.rancher.com/server-charts/stable
  effective_rancher_repo_url = (
    var.rancher_repo_url != "" ? var.rancher_repo_url :
    (local.harbor_oci_available && var.rancher_source == "oci" ? local.harbor_oci_repo_argocd : (
      var.rancher_source == "external" ? "https://releases.rancher.com/server-charts/stable" : ""
    ))
  )
  
  rancher_repository = local.harbor_oci_available ? local.harbor_oci_url : var.rancher_repo_url
  rancher_chart      = "rancher"
}

# -----------------------------------------------------------------------------
# Pre-seed Helm charts into Harbor OCI (LOCAL MACHINE)
# - Harbor EC2의 user_data seeding이 아직 완료되지 않았거나(비동기),
#   이전 배포에서 seed 스크립트가 실패한 경우에도 55-bootstrap이 진행되도록 보강
# - 로컬 머신에서 Helm CLI가 설치되어 있고, 인터넷/외부 helm repo 접근이 가능하다는 전제
# -----------------------------------------------------------------------------
resource "null_resource" "seed_missing_helm_charts" {

  triggers = {
    harbor_host         = local.harbor_oci_host
    argocd_version      = var.argocd_version
    cert_manager_version = var.cert_manager_version
    rancher_chart_version = var.rancher_chart_version
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-lc"]
    command = <<-EOC
set -euo pipefail

HARBOR_HOST='${local.harbor_oci_host}'
ADMIN_PASS='${var.harbor_admin_password}'
PROJECT='helm-charts'

ENABLE_SEED='${local.harbor_oci_available && var.auto_seed_missing_helm_charts}'
if [[ "$ENABLE_SEED" != "true" ]]; then
  echo "[seed] auto seeding disabled or Harbor OCI not available. Skip."
  exit 0
fi


# Wait for Harbor registry endpoint to be reachable (401/403/200 are OK)
echo "[seed] Waiting for Harbor registry endpoint: https://$HARBOR_HOST/v2/"
for i in $(seq 1 60); do
  code="$(curl -ks -o /dev/null -w '%{http_code}' "https://$HARBOR_HOST/v2/" || true)"
  if [[ "$code" == "200" || "$code" == "401" || "$code" == "403" ]]; then
    echo "[seed] Harbor /v2 ready (HTTP $code)"
    break
  fi
  sleep 2
done
if [[ -z "$HARBOR_HOST" ]]; then
  echo "[seed] Harbor host is empty. Skip."
  exit 0
fi

echo "[seed] Ensuring Harbor project '$PROJECT' exists (best-effort)"
curl -fsS -u "admin:$ADMIN_PASS" -X POST "https://$HARBOR_HOST/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -d '{"project_name":"'"$PROJECT"'","public":true}' >/dev/null 2>&1 || true

echo "[seed] Helm registry login: $HARBOR_HOST"
echo "$ADMIN_PASS" | helm registry login "$HARBOR_HOST" -u admin --password-stdin >/dev/null

ensure_chart() {
  local alias="$1" repo="$2" chart="$3" ver="$4"

  if helm show chart "oci://$HARBOR_HOST/$PROJECT/$chart" --version "$ver" >/dev/null 2>&1; then
    echo "[seed] OK: $chart:$ver already exists in Harbor OCI"
    return 0
  fi

  echo "[seed] Missing: $chart:$ver -> pull from $repo and push to Harbor OCI"
  helm repo add "$alias" "$repo" --force-update >/dev/null
  helm repo update >/dev/null
  rm -rf /tmp/harbor-oci-seed && mkdir -p /tmp/harbor-oci-seed
  helm pull "$alias/$chart" --version "$ver" -d /tmp/harbor-oci-seed
  helm push "/tmp/harbor-oci-seed/${chart}-${ver}.tgz" "oci://$HARBOR_HOST/$PROJECT" >/dev/null
  rm -rf /tmp/harbor-oci-seed
}

ensure_chart "argo" "https://argoproj.github.io/argo-helm" "argo-cd" "${var.argocd_version}"
ensure_chart "jetstack" "https://charts.jetstack.io" "cert-manager" "${var.cert_manager_version}"
ensure_chart "rancher" "https://releases.rancher.com/server-charts/stable" "rancher" "${var.rancher_chart_version}"

helm repo remove argo jetstack rancher >/dev/null 2>&1 || true
echo "[seed] Done"
EOC
  }
}

# -----------------------------------------------------------------------------
# AWS Provider
# -----------------------------------------------------------------------------
provider "aws" {
  region = var.region
}

# -----------------------------------------------------------------------------
# Kubernetes & Helm Provider 설정
# kubeconfig 파일 기반 연결 (Bastion에서 실행 또는 로컬에서 kubeconfig 복사 후 실행)
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# Local Variables
# -----------------------------------------------------------------------------
locals {
  effective_base_domain = var.base_domain != "" ? var.base_domain : var.domain
  argocd_hostname = local.effective_base_domain != "" ? "${var.argocd_subdomain}.${local.effective_base_domain}" : ""
  rancher_hostname = local.effective_base_domain != "" ? "${var.rancher_subdomain}.${local.effective_base_domain}" : ""
  
  common_labels = {
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "bootstrap"
    "environment"                  = var.env
    "project"                      = var.project
  }
}

# -----------------------------------------------------------------------------
# 1. cert-manager 설치 (선택적)
# -----------------------------------------------------------------------------
# cert-manager 자동 감지: 이미 설치되어 있으면 Helm 설치를 스킵하여
# "cannot re-use a name that is still in use" 에러를 방지합니다.
data "external" "cert_manager_probe" {
  count = var.cert_manager_skip_if_present ? 1 : 0

  program = ["python3", "${path.module}/scripts/check_cert_manager_installed.py"]

  query = {
    kubeconfig_path    = var.kubeconfig_path
    kubeconfig_context = var.kubeconfig_context != null ? var.kubeconfig_context : ""
    namespace          = "cert-manager"
  }
}

locals {
  cert_manager_already_installed = var.cert_manager_skip_if_present ? (try(data.external.cert_manager_probe[0].result.installed, "false") == "true") : false
  install_cert_manager_effective = var.install_cert_manager && !local.cert_manager_already_installed
}

resource "helm_release" "cert_manager" {
  count = local.install_cert_manager_effective ? 1 : 0
  depends_on = [null_resource.seed_missing_helm_charts]

  name             = "cert-manager"
  repository       = local.certmanager_repository
  chart            = local.certmanager_chart
  version          = var.cert_manager_version
  namespace        = "cert-manager"
  create_namespace = true
  
  # OCI 레지스트리 사용 시 TLS 스킵 (Harbor HTTP)
  repository_username = local.harbor_oci_available ? "admin" : null
  repository_password = local.harbor_oci_available ? var.harbor_admin_password : null

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "webhook.timeoutSeconds"
    value = "30"
  }

  # DNS01 solver를 위한 설정 (Route53)
  set {
    name  = "extraArgs[0]"
    value = "--dns01-recursive-nameservers-only"
  }

  set {
    name  = "extraArgs[1]"
    value = "--dns01-recursive-nameservers=8.8.8.8:53\\,1.1.1.1:53"
  }

  wait          = true
  wait_for_jobs = true
  timeout       = 600

  depends_on = [null_resource.seed_missing_helm_charts]

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# 2. ArgoCD 설치
# -----------------------------------------------------------------------------
resource "helm_release" "argocd" {
  depends_on = [null_resource.seed_missing_helm_charts]
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
      name  = "server.ingress.annotations.nginx\.ingress\.kubernetes\.io/ssl-redirect"
      value = "false"
    }
  }

  dynamic "set" {
    for_each = var.argocd_enable_ingress ? [1] : []
    content {
      name  = "server.ingress.annotations.nginx\.ingress\.kubernetes\.io/force-ssl-redirect"
      value = "false"
    }
  }

  dynamic "set" {
    for_each = var.argocd_enable_ingress ? [1] : []
    content {
      name  = "server.ingress.annotations.nginx\.ingress\.kubernetes\.io/backend-protocol"
      value = "HTTP"
    }
  }

  dynamic "set" {
    for_each = var.argocd_enable_ingress ? [1] : []
    content {
      name  = "server.ingress.annotations.nginx\.ingress\.kubernetes\.io/configuration-snippet"
      value = "proxy_set_header X-Forwarded-Proto \"https\";\nproxy_set_header X-Forwarded-Port \"443\";\nproxy_set_header X-Forwarded-Ssl \"on\";"
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

  wait    = true
  timeout = 600

  depends_on = [null_resource.seed_missing_helm_charts, helm_release.cert_manager]
}

################################################################################
# ArgoCD External Access via ingress-nginx (Public NLB + ACM TLS Termination)
# - NLB에서 TLS 종료 후 ingress-nginx(NodePort)로 HTTP 전달되는 구조 전제
# - Host 기반: https://argocd.<domain>
################################################################################

resource "kubectl_manifest" "argocd_ingress" {
  count = var.argocd_enable_ingress && local.argocd_hostname != "" ? 1 : 0

  yaml_body = <<-YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd
  namespace: ${var.argocd_namespace}
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
    nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
    nginx.ingress.kubernetes.io/configuration-snippet: |
      proxy_set_header X-Forwarded-Proto "https";
      proxy_set_header X-Forwarded-Port "443";
      proxy_set_header X-Forwarded-Ssl "on";
spec:
  ingressClassName: ${var.argocd_ingress_class_name}
  rules:
  - host: ${local.argocd_hostname}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
YAML

  depends_on = [
    helm_release.argocd
  ]
}



# -----------------------------------------------------------------------------
# 3. ArgoCD Initial Admin Password (Data Source)
# -----------------------------------------------------------------------------
data "kubernetes_secret" "argocd_initial_admin" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = var.argocd_namespace
  }

  depends_on = [helm_release.argocd]
}

# -----------------------------------------------------------------------------
# 4. ArgoCD Root Application (App-of-Apps Pattern) - Optional
# -----------------------------------------------------------------------------
resource "kubectl_manifest" "argocd_root_app" {
  count = var.enable_gitops_apps && var.gitops_repo_url != "" ? 1 : 0

  yaml_body = <<-YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-apps
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  labels:
    app.kubernetes.io/managed-by: terraform
    app.kubernetes.io/part-of: gitops
spec:
  project: default
  source:
    repoURL: ${var.gitops_repo_url}
    targetRevision: ${var.gitops_repo_branch}
    path: ${var.gitops_apps_path}
  destination:
    server: https://kubernetes.default.svc
    namespace: ${var.argocd_namespace}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - PruneLast=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
YAML

  depends_on = [helm_release.argocd]
}

################################################################################
# Optional: Rancher install via ArgoCD (no external GitOps repo required)
# - enable_rancher_app=true + rancher_bootstrap_password 설정 시에만 생성
# - Host 기반: https://rancher.<domain>
################################################################################


# -----------------------------------------------------------------------------
# ArgoCD Repository: Harbor OCI Helm Charts (enableOCI=true)
# - Harbor는 내부적으로 HTTP일 수 있으나, ALB+ACM(HTTPS) 엔드포인트를 사용하면
#   ArgoCD/Helm/Provider가 OCI 레지스트리에 안정적으로 접근할 수 있습니다.
# -----------------------------------------------------------------------------
resource "kubectl_manifest" "argocd_harbor_oci_repo" {
  count = local.harbor_oci_available ? 1 : 0

  yaml_body = <<-YAML
apiVersion: v1
kind: Secret
metadata:
  name: harbor-oci-helm
  namespace: ${var.argocd_namespace}
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  name: harbor-oci-helm
  type: helm
  # NOTE: ArgoCD에서는 OCI Helm repo 등록 시 oci:// prefix를 제거하고, registry host만 지정하는 것을 권장합니다.
  #       (chart path는 Application의 repoURL에 포함)
  url: ${local.harbor_oci_host}
  enableOCI: "true"
  username: admin
  password: ${var.harbor_admin_password}
YAML

  depends_on = [
    helm_release.argocd
  ]
}


# -----------------------------------------------------------------------------
# Rancher Installation (ArgoCD)
# - 내부 완결 옵션:
#   * OCI (Harbor에 시딩된 Helm Chart)
#   * Git (내부 GitOps repo)
# -----------------------------------------------------------------------------
resource "kubectl_manifest" "argocd_rancher_app_helm" {
  count = var.enable_rancher_app && local.rancher_hostname != "" && var.rancher_bootstrap_password != "" && var.rancher_source != "git" && local.effective_rancher_repo_url != "" ? 1 : 0

  yaml_body = <<-YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rancher
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  annotations:
    argocd.argoproj.io/sync-wave: "10"
spec:
  project: default
  source:
    repoURL: ${local.effective_rancher_repo_url}
    chart: rancher
    targetRevision: ${var.rancher_chart_version}
    helm:
      releaseName: rancher
      valuesObject:
        hostname: ${local.rancher_hostname}
        tls: external
        bootstrapPassword: ${var.rancher_bootstrap_password}
        ingress:
          enabled: true
          ingressClassName: ${var.rancher_ingress_class_name}
          extraAnnotations:
            nginx.ingress.kubernetes.io/ssl-redirect: "false"
            nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
            nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
            nginx.ingress.kubernetes.io/proxy-read-timeout: "1800"
            nginx.ingress.kubernetes.io/proxy-send-timeout: "1800"
            nginx.ingress.kubernetes.io/configuration-snippet: |
              proxy_set_header X-Forwarded-Proto "https";
              proxy_set_header X-Forwarded-Port "443";
              proxy_set_header X-Forwarded-Ssl "on";
  destination:
    server: https://kubernetes.default.svc
    namespace: ${var.rancher_namespace}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
YAML

  depends_on = [
    helm_release.argocd,
    kubectl_manifest.argocd_harbor_oci_repo
  ]}

resource "kubectl_manifest" "argocd_rancher_app_git" {
  count = var.enable_rancher_app && local.rancher_hostname != "" && var.rancher_bootstrap_password != "" && var.rancher_source == "git" && var.rancher_git_repo_url != "" ? 1 : 0

  yaml_body = <<-YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rancher
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  annotations:
    argocd.argoproj.io/sync-wave: "10"
spec:
  project: default
  source:
    repoURL: ${var.rancher_git_repo_url}
    targetRevision: ${var.rancher_git_revision}
    path: ${var.rancher_git_path}
  destination:
    server: https://kubernetes.default.svc
    namespace: ${var.rancher_namespace}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
YAML

  depends_on = [
    helm_release.argocd
  ]
}



# -----------------------------------------------------------------------------
# 5. ArgoCD Repository Secret (Private Git Repo) - Optional
# -----------------------------------------------------------------------------
resource "kubernetes_secret" "argocd_repo_creds" {
  count = var.enable_gitops_apps && var.gitops_repo_ssh_private_key != "" ? 1 : 0

  metadata {
    name      = "repo-creds"
    namespace = var.argocd_namespace
    labels = {
      "argocd.argoproj.io/secret-type" = "repo-creds"
    }
  }

  data = {
    type          = "git"
    url           = var.gitops_repo_url
    sshPrivateKey = base64decode(var.gitops_repo_ssh_private_key)
  }

  depends_on = [helm_release.argocd]
}
