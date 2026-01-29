# ==============================================================================
# 55-bootstrap Variables
#
# Naming Convention:
#   - snake_case for all variable names
#   - standard prefixes: argocd_, harbor_, gitops_
# ==============================================================================

# ------------------------------------------------------------------------------
# Universal Variables
# ------------------------------------------------------------------------------

variable "env" {
  description = "환경 (dev/staging/prod)"
  type        = string
}

variable "project" {
  description = "프로젝트/조직 식별자"
  type        = string
}

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-2"
}

variable "state_bucket" {
  description = "Terraform remote state S3 bucket"
  type        = string
}

variable "state_region" {
  description = "Terraform remote state S3 region"
  type        = string
}

variable "state_key_prefix" {
  description = "Terraform remote state key prefix"
  type        = string
}

variable "azs" {
  description = "Multi-AZ 사용 목록"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

################################################################################
# Kubernetes Connection
################################################################################

variable "kubeconfig_path" {
  description = "kubeconfig 파일 경로 (Bastion에서 복사한 파일)"
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = "kubeconfig context 이름 (null이면 current-context 사용)"
  type        = string
  default     = null
}

# ------------------------------------------------------------------------------
# 2. Harbor OCI Integration (for Helm Charts)
# ------------------------------------------------------------------------------

variable "use_harbor_oci" {
  description = "Harbor OCI 레지스트리에서 Helm 차트 설치 여부 (외부 네트워크 접근 불가 시 true)"
  type        = bool
  default     = true
}

variable "harbor_oci_registry_url" {
  description = "Harbor OCI 레지스트리 URL (빈 값이면 45-harbor remote state에서 자동 감지)"
  type        = string
  default     = ""
}

variable "harbor_admin_password" {
  description = "Harbor admin 비밀번호 (OCI 레지스트리 인증용)"
  type        = string
  default     = "Harbor12345"
  sensitive   = true
}

variable "auto_seed_missing_helm_charts" {
  description = "Harbor OCI 사용 시, 필요한 Helm 차트(argo-cd/cert-manager/rancher)가 Harbor에 없으면 로컬 머신에서 외부 Helm repo에서 pull 후 Harbor OCI로 push하여 채웁니다. (로컬 머신에서 실행 + 인터넷 가능 전제)"
  type        = bool
  default     = true
}

# Cert-Manager Variables removed (ArgoCD managed)

# ------------------------------------------------------------------------------
# 1. ArgoCD Configuration
# ------------------------------------------------------------------------------

variable "argocd_version" {
  description = "ArgoCD Helm 차트 버전"
  type        = string
  default     = "5.55.0"
}

variable "argocd_namespace" {
  description = "ArgoCD 설치 namespace"
  type        = string
  default     = "argocd"
}

variable "argocd_ha_enabled" {
  description = "ArgoCD HA 모드 활성화 (Production 권장)"
  type        = bool
  default     = false
}

variable "argocd_server_replicas" {
  description = "ArgoCD Server 레플리카 수"
  type        = number
  default     = 1
}

variable "argocd_nodeport_http" {
  description = "ArgoCD Server HTTP NodePort"
  type        = number
  default     = 31080
}

variable "argocd_nodeport_https" {
  description = "ArgoCD Server HTTPS NodePort"
  type        = number
  default     = 31443
}

variable "argocd_server_insecure" {
  description = "ArgoCD Server insecure 모드 (NLB에서 TLS 종료 시 true)"
  type        = bool
  default     = true
}

################################################################################
# GitOps Configuration (App-of-Apps Pattern)
################################################################################

variable "enable_gitops_apps" {
  description = "GitOps App-of-Apps 패턴 활성화"
  type        = bool
  default     = false
}

variable "gitops_repo_url" {
  description = "GitOps 저장소 URL (예: https://github.com/org/repo.git)"
  type        = string
  default     = ""
}

variable "gitops_repo_branch" {
  description = "GitOps 저장소 브랜치"
  type        = string
  default     = "main"
}

variable "gitops_apps_path" {
  description = "GitOps 저장소 내 앱 경로"
  type        = string
  default     = "gitops-apps/platform"
}

variable "gitops_repo_ssh_private_key" {
  description = "Private Git 저장소 SSH 키 (Base64 인코딩)"
  type        = string
  default     = ""
  sensitive   = true
}

################################################################################
# Domain & DNS
################################################################################

variable "base_domain" {
  description = "루트 도메인 (예: example.com). argocd/rancher 호스트네임 구성에 사용됩니다."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-z0-9.-]+$", var.base_domain))
    error_message = "도메인 형식은 소문자, 숫자, 점(.), 하이픈(-)만 허용됩니다."
  }
}

variable "domain" {
  description = "기본 도메인 (예: example.com)"
  type        = string
  default     = ""
}

variable "argocd_subdomain" {
  description = "ArgoCD 서브도메인 (예: argocd → argocd.example.com)"
  type        = string
  default     = "argocd"
}


variable "argocd_enable_ingress" {
  description = "ArgoCD UI를 ingress-nginx(host 기반)로 노출할지 여부 (NLB + ACM TLS 종료 전제)"
  type        = bool
  default     = true
}

variable "argocd_ingress_class_name" {
  description = "ArgoCD IngressClass 이름"
  type        = string
  default     = "nginx"
}

variable "enable_route53_argocd_alias" {
  description = "ArgoCD DNS 레코드(A Alias) 자동 생성 여부"
  type        = bool
  default     = true
}

variable "route53_zone_id" {
  description = "Route53 Hosted Zone ID (빈 값이면 base_domain으로 자동 조회)"
  type        = string
  default     = ""
}

variable "route53_private_zone" {
  description = "Route53 Hosted Zone이 사설(Private) 인지 여부"
  type        = bool
  default     = false
}

# Rancher Configuration removed (ArgoCD managed)

################################################################################
# Resource Limits
################################################################################

variable "argocd_resources" {
  description = "ArgoCD 컴포넌트 리소스 설정"
  type = object({
    server = object({
      requests = object({
        cpu    = string
        memory = string
      })
      limits = object({
        cpu    = string
        memory = string
      })
    })
    controller = object({
      requests = object({
        cpu    = string
        memory = string
      })
      limits = object({
        cpu    = string
        memory = string
      })
    })
    repo_server = object({
      requests = object({
        cpu    = string
        memory = string
      })
      limits = object({
        cpu    = string
        memory = string
      })
    })
  })
  default = {
    server = {
      requests = { cpu = "100m", memory = "128Mi" }
      limits   = { cpu = "500m", memory = "512Mi" }
    }
    controller = {
      requests = { cpu = "250m", memory = "256Mi" }
      limits   = { cpu = "1000m", memory = "1Gi" }
    }
    repo_server = {
      requests = { cpu = "100m", memory = "128Mi" }
      limits   = { cpu = "500m", memory = "512Mi" }
    }
  }
}
