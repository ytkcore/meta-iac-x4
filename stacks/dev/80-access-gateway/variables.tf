# =============================================================================
# 80-access-gateway Stack - Variables
# =============================================================================

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "env" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "meta"
}

variable "base_domain" {
  description = "Base domain for services"
  type        = string
}

variable "state_bucket" {
  description = "Terraform state bucket"
  type        = string
}

variable "state_region" {
  description = "Terraform state bucket region"
  type        = string
  default     = "ap-northeast-2"
}

variable "state_key_prefix" {
  description = "Terraform state key prefix"
  type        = string
  default     = "iac"
}

# -----------------------------------------------------------------------------
# Access Solution Selection
# -----------------------------------------------------------------------------
variable "access_solution" {
  description = "Access control solution to use (teleport, none)"
  type        = string
  default     = "teleport"

  validation {
    condition     = contains(["teleport", "none"], var.access_solution)
    error_message = "access_solution must be one of: teleport, none"
  }
}

# -----------------------------------------------------------------------------
# Kubernetes Services (GitOps 배포, 수동 등록 필요)
# -----------------------------------------------------------------------------
variable "kubernetes_services" {
  description = "Kubernetes services to register (manually specified, not auto-discovered)"
  type = list(object({
    name             = string
    uri              = string
    type             = optional(string, "web")
    internal         = optional(bool, true)
    display_name     = optional(string, "")
    description      = optional(string, "")
    rewrite_redirect = optional(list(string), [])
  }))
  default = [
    {
      name         = "argocd"
      uri          = "https://argocd.unifiedmeta.net"
      type         = "web"
      internal     = true
      display_name = "ArgoCD — GitOps 배포"
    },
    {
      name         = "grafana"
      uri          = "https://grafana.unifiedmeta.net"
      type         = "web"
      internal     = true
      display_name = "Grafana — 모니터링 대시보드"
    },
    {
      name         = "longhorn"
      uri          = "https://longhorn.unifiedmeta.net"
      type         = "web"
      internal     = true
      display_name = "Longhorn — 분산 스토리지"
    },
    {
      name         = "rancher"
      uri          = "https://rancher.unifiedmeta.net"
      type         = "web"
      internal     = true
      display_name = "Rancher — 클러스터 관리"
    },
    {
      name         = "vault"
      uri          = "https://vault.dev.unifiedmeta.net"
      type         = "web"
      internal     = true
      display_name = "Vault — 시크릿 관리"
    },
    {
      name              = "keycloak-admin"
      uri               = "https://keycloak.dev.unifiedmeta.net"
      type              = "web"
      internal          = true
      display_name      = "Keycloak — SSO 관리 콘솔"
      rewrite_redirect  = ["keycloak.dev.unifiedmeta.net"]
    },
    {
      name         = "alertmanager"
      uri          = "https://alertmanager.unifiedmeta.net"
      type         = "web"
      internal     = true
      display_name = "Alertmanager — 알림 관리"
    },
    {
      name         = "prometheus"
      uri          = "https://prometheus.unifiedmeta.net"
      type         = "web"
      internal     = true
      display_name = "Prometheus — 메트릭 수집"
    },
    {
      name         = "opstart"
      uri          = "https://opstart.unifiedmeta.net"
      type         = "web"
      internal     = true
      display_name = "OpStart — 운영 온보딩"
    },
    {
      name         = "aipp"
      uri          = "https://aipp.dev.unifiedmeta.net"
      type         = "web"
      internal     = true
      display_name = "AIPP — AI 플랫폼 포탈"
    },
    {
      name         = "home"
      uri          = "https://home.unifiedmeta.net"
      type         = "web"
      internal     = true
      display_name = "Home — 랜딩 페이지"
    },
    {
      name         = "dashboard"
      uri          = "https://dashboard.unifiedmeta.net"
      type         = "web"
      internal     = true
      display_name = "Dashboard — 플랫폼 현황"
    }
  ]
}
