################################################################################
# Rancher Module - Terraform + Helm Provider
# 
# 글로벌 베스트 프랙티스:
# 1. Terraform Helm Provider를 통한 초기 부트스트랩 (Day 1)
# 2. cert-manager → Rancher 순차 설치
# 3. 이후 Day 2 Operations는 GitOps(Fleet/ArgoCD)로 전환 권장
#
# TLS 옵션:
# 1. rancher     - Rancher 자체 CA + cert-manager
# 2. letsEncrypt - Let's Encrypt + cert-manager  
# 3. secret      - 외부 인증서 (K8s Secret)
# 4. external    - 외부 LB에서 TLS 종료 (AWS ACM 등)
#
# 참고:
# - SUSE/Rancher 공식 문서: https://ranchermanager.docs.rancher.com
# - cert-manager 공식 문서: https://cert-manager.io/docs/installation/helm/
################################################################################

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.25.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.10.0"
    }
  }
}

locals {
  common_labels = merge(
    {
      "app.kubernetes.io/managed-by" = "terraform"
      "project"                      = var.project
      "environment"                  = var.env
    },
    var.labels
  )

  # Rancher hostname 결정
  rancher_hostname = var.rancher_hostname != null ? var.rancher_hostname : "${var.rancher_subdomain}.${var.domain}"

  # External TLS termination 사용 시 cert-manager 불필요
  install_cert_manager = !var.skip_cert_manager && !var.external_tls_termination && var.tls_source != "external"

  # TLS source 결정 (external의 경우 secret으로 처리하되 ingress에서 TLS 비활성화)
  effective_tls_source = var.external_tls_termination || var.tls_source == "external" ? "secret" : var.tls_source
# extra_env(map)을 Helm chart의 extraEnv(list)로 변환
extra_env_list     = [for k, v in var.extra_env : { name = k, value = v }]
extra_env_by_index = { for idx, kv in local.extra_env_list : idx => kv }

# Kubernetes 1.29+에서 Rancher chart 2.8.x 등은 kubeVersion 제약으로 실패하므로 방지
rancher_version_supported = can(regex("^2\\.(1[2-9]|[2-9][0-9])\\.[0-9]+.*$", var.rancher_version))

}

################################################################################
# cert-manager Namespace & Installation
# Rancher는 TLS 인증서 관리를 위해 cert-manager가 필수 (external TLS 제외)
################################################################################

resource "kubernetes_namespace_v1" "cert_manager" {
  count = local.install_cert_manager ? 1 : 0

  metadata {
    name = "cert-manager"
    labels = merge(local.common_labels, {
      "app.kubernetes.io/name" = "cert-manager"
    })
  }
}

# cert-manager CRDs는 Helm 차트에서 설치하도록 설정
resource "helm_release" "cert_manager" {
  count = local.install_cert_manager ? 1 : 0

  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.cert_manager_version
  namespace  = kubernetes_namespace_v1.cert_manager[0].metadata[0].name

  # CRDs 설치 활성화
  set {
    name  = "installCRDs"
    value = "true"
  }

  # Private Registry 사용 시 (Harbor 연동)
  dynamic "set" {
    for_each = var.private_registry != null ? [1] : []
    content {
      name  = "image.repository"
      value = "${var.private_registry}/quay.io/jetstack/cert-manager-controller"
    }
  }

  dynamic "set" {
    for_each = var.private_registry != null ? [1] : []
    content {
      name  = "webhook.image.repository"
      value = "${var.private_registry}/quay.io/jetstack/cert-manager-webhook"
    }
  }

  dynamic "set" {
    for_each = var.private_registry != null ? [1] : []
    content {
      name  = "cainjector.image.repository"
      value = "${var.private_registry}/quay.io/jetstack/cert-manager-cainjector"
    }
  }

  dynamic "set" {
    for_each = var.private_registry != null ? [1] : []
    content {
      name  = "startupapicheck.image.repository"
      value = "${var.private_registry}/quay.io/jetstack/cert-manager-startupapicheck"
    }
  }

  # Resource limits/requests
  set {
    name  = "resources.requests.cpu"
    value = var.cert_manager_resources.requests.cpu
  }

  set {
    name  = "resources.requests.memory"
    value = var.cert_manager_resources.requests.memory
  }

  set {
    name  = "resources.limits.cpu"
    value = var.cert_manager_resources.limits.cpu
  }

  set {
    name  = "resources.limits.memory"
    value = var.cert_manager_resources.limits.memory
  }

  # Webhook 설정
  set {
    name  = "webhook.timeoutSeconds"
    value = "30"
  }

  # DNS01 solver를 위한 Pod DNS Policy (Private subnet 환경)
  set {
    name  = "podDnsPolicy"
    value = "None"
  }

  set {
    name  = "podDnsConfig.nameservers[0]"
    value = var.dns_server
  }

  wait          = true
  wait_for_jobs = true
  timeout       = 600

  depends_on = [kubernetes_namespace_v1.cert_manager]
}

# cert-manager가 완전히 준비될 때까지 대기
resource "time_sleep" "wait_for_cert_manager" {
  count = local.install_cert_manager ? 1 : 0

  depends_on = [helm_release.cert_manager]

  create_duration = "30s"
}

################################################################################
# Rancher Namespace & Installation
################################################################################

resource "kubernetes_namespace_v1" "cattle_system" {
  metadata {
    name = "cattle-system"
    labels = merge(local.common_labels, {
      "app.kubernetes.io/name" = "rancher"
    })
  }
}

resource "helm_release" "rancher" {
  name       = "rancher"
  repository = var.rancher_helm_repo
  chart      = "rancher"
  version    = var.rancher_version
  namespace  = kubernetes_namespace_v1.cattle_system.metadata[0].name

  lifecycle {
    precondition {
      condition     = local.rancher_version_supported
      error_message = "rancher_version (${var.rancher_version}) is too old and will fail on Kubernetes >= 1.29 (e.g., v1.33) due to chart kubeVersion constraints. Use Rancher 2.12+ (example: 2.13.1) or downgrade Kubernetes."
    }
  }


  # 필수 설정
  set {
    name  = "hostname"
    value = local.rancher_hostname
  }

  set {
    name  = "bootstrapPassword"
    value = var.bootstrap_password
  }

  set {
    name  = "replicas"
    value = var.rancher_replicas
  }

  # TLS 설정
  # external TLS termination의 경우 ingress.tls.source=secret 사용하되 실제 인증서는 불필요
  set {
    name  = "ingress.tls.source"
    value = local.effective_tls_source
  }

  # External TLS Termination 설정 (AWS NLB + ACM 등)
  # tls: external로 설정하면 Rancher가 HTTP로 동작하고 LB에서 TLS 처리
  dynamic "set" {
    for_each = var.external_tls_termination || var.tls_source == "external" ? [1] : []
    content {
      name  = "tls"
      value = "external"
    }
  }

  # cert-manager 버전 명시 (Rancher 호환성) - cert-manager 설치 시에만
  # Let's Encrypt 설정 (tls_source가 letsEncrypt일 때)
  dynamic "set" {
    for_each = var.tls_source == "letsEncrypt" ? [1] : []
    content {
      name  = "letsEncrypt.email"
      value = var.letsencrypt_email
    }
  }

  dynamic "set" {
    for_each = var.tls_source == "letsEncrypt" ? [1] : []
    content {
      name  = "letsEncrypt.ingress.class"
      value = var.ingress_class_name
    }
  }

  dynamic "set" {
    for_each = var.tls_source == "letsEncrypt" && var.letsencrypt_environment != "production" ? [1] : []
    content {
      name  = "letsEncrypt.environment"
      value = var.letsencrypt_environment
    }
  }

  # Private CA 사용 시
  dynamic "set" {
    for_each = var.private_ca ? [1] : []
    content {
      name  = "privateCA"
      value = "true"
    }
  }

  # Private Registry 설정 (Harbor 연동)
  dynamic "set" {
    for_each = var.private_registry != null ? [1] : []
    content {
      name  = "rancherImage"
      value = "${var.private_registry}/rancher/rancher"
    }
  }

  dynamic "set" {
    for_each = var.private_registry != null ? [1] : []
    content {
      name  = "systemDefaultRegistry"
      value = var.private_registry
    }
  }

  # Air-gap 환경에서 bundled system charts 사용
  dynamic "set" {
    for_each = var.use_bundled_system_chart ? [1] : []
    content {
      name  = "useBundledSystemChart"
      value = "true"
    }
  }

  # Ingress Class 설정
  set {
    name  = "ingress.ingressClassName"
    value = var.ingress_class_name
  }

  # External TLS 사용 시 Ingress에 특수 annotation 추가
  # nginx ingress controller가 백엔드로 HTTP 사용하도록 설정
  dynamic "set" {
    for_each = var.external_tls_termination || var.tls_source == "external" ? [1] : []
    content {
      name  = "ingress.extraAnnotations.nginx\\.ingress\\.kubernetes\\.io/ssl-redirect"
      value = "false"
      type  = "string"
    }
  }

  dynamic "set" {
    for_each = var.external_tls_termination || var.tls_source == "external" ? [1] : []
    content {
      name  = "ingress.extraAnnotations.nginx\\.ingress\\.kubernetes\\.io/backend-protocol"
      value = "HTTP"
      type  = "string"
    }
  }

  # Audit Log 설정
  dynamic "set" {
    for_each = var.enable_audit_log ? [1] : []
    content {
      name  = "auditLog.level"
      value = var.audit_log_level
    }
  }

  dynamic "set" {
    for_each = var.enable_audit_log ? [1] : []
    content {
      name  = "auditLog.destination"
      value = var.audit_log_destination
    }
  }

  # Resource limits
  set {
    name  = "resources.requests.cpu"
    value = var.rancher_resources.requests.cpu
  }

  set {
    name  = "resources.requests.memory"
    value = var.rancher_resources.requests.memory
  }

  set {
    name  = "resources.limits.cpu"
    value = var.rancher_resources.limits.cpu
  }

  set {
    name  = "resources.limits.memory"
    value = var.rancher_resources.limits.memory
  }

  # Extra 환경변수 (Proxy 설정 등)
  dynamic "set" {
  for_each = local.extra_env_by_index
  content {
    name  = "extraEnv[${set.key}].name"
    value = set.value.name
  }
}

dynamic "set" {
  for_each = local.extra_env_by_index
  content {
    name  = "extraEnv[${set.key}].value"
    value = set.value.value
  }
}

# Anti-affinity 설정 (HA)
  set {
    name  = "antiAffinity"
    value = var.rancher_replicas > 1 ? "required" : "preferred"
  }

  wait          = true
  wait_for_jobs = true
  timeout       = 900

  depends_on = [
    time_sleep.wait_for_cert_manager,
    kubernetes_namespace_v1.cattle_system
  ]
}

################################################################################
# Optional: ClusterIssuer for Let's Encrypt (self-signed 외 옵션)
################################################################################

resource "kubectl_manifest" "cluster_issuer_letsencrypt" {
  count = var.create_cluster_issuer && var.tls_source == "letsEncrypt" && local.install_cert_manager ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: ${var.letsencrypt_environment == "production" ? "letsencrypt-prod" : "letsencrypt-staging"}
    spec:
      acme:
        server: ${var.letsencrypt_environment == "production" ? "https://acme-v02.api.letsencrypt.org/directory" : "https://acme-staging-v02.api.letsencrypt.org/directory"}
        email: ${var.letsencrypt_email}
        privateKeySecretRef:
          name: ${var.letsencrypt_environment == "production" ? "letsencrypt-prod-account-key" : "letsencrypt-staging-account-key"}
        solvers:
          - http01:
              ingress:
                class: ${var.ingress_class_name}
  YAML

  depends_on = [time_sleep.wait_for_cert_manager]
}

################################################################################
# Optional: Self-signed ClusterIssuer (내부망용)
################################################################################

resource "kubectl_manifest" "cluster_issuer_selfsigned" {
  count = var.create_cluster_issuer && var.tls_source == "rancher" && local.install_cert_manager ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: selfsigned-issuer
    spec:
      selfSigned: {}
  YAML

  depends_on = [time_sleep.wait_for_cert_manager]
}