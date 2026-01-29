################################################################################
# 55-bootstrap Stack Variables
#
# DevSecOps Best Practice:
# - Infrastructure Bootstrap은 Terraform으로 코드화
# - Day-2 Operations는 ArgoCD GitOps로 위임
################################################################################

################################################################################
# Common Variables (env.tfvars에서 주입)
################################################################################

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

################################################################################
# Harbor OCI Registry (Helm Charts)
################################################################################

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

################################################################################
# cert-manager Configuration
################################################################################

variable "cert_manager_version" {
  description = "cert-manager Helm 차트 버전"
  type        = string
  default     = "v1.14.5"
}

variable "install_cert_manager" {
  description = "cert-manager 설치 여부 (External TLS Termination 시 false 가능)"
  type        = bool
  default     = false
}

variable "cert_manager_skip_if_present" {
  description = "true이면 클러스터에 cert-manager가 이미 설치되어 있을 때(예: helm/manual/ArgoCD) 설치를 자동으로 스킵합니다. install_cert_manager=true여도 충돌을 방지합니다."
  type        = bool
  default     = true
}

################################################################################
# ArgoCD Configuration
################################################################################

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

variable "enable_rancher_app" {
  description = "ArgoCD를 통해 Rancher Application을 생성(설치)할지 여부 (GitOps repo를 쓰지 않는 간편 부트스트랩용)"
  type        = bool
  default     = false
}

variable "rancher_subdomain" {
  description = "Rancher 서브도메인 (예: rancher → rancher.example.com)"
  type        = string
  default     = "rancher"
}

variable "rancher_namespace" {
  description = "Rancher 설치 네임스페이스"
  type        = string
  default     = "cattle-system"
}

variable "rancher_repo_url" {
  description = "Rancher Helm Repository URL"
  type        = string
  default     = ""
}

variable "rancher_source" {
  description = "Rancher 설치 소스 타입: oci(권장), git(내부 GitOps), external(외부 Helm repo)"
  type        = string
  default     = "oci"
}

variable "rancher_git_repo_url" {
  description = "Rancher 매니페스트/헬름 차트 래퍼를 호스팅하는 내부 Git repo URL (rancher_source=git일 때)"
  type        = string
  default     = ""
}

variable "rancher_git_path" {
  description = "Git repo 내 Rancher 디렉토리 경로 (rancher_source=git일 때)"
  type        = string
  default     = "platform/rancher"
}

variable "rancher_git_revision" {
  description = "Git repo revision (branch/tag/commit)"
  type        = string
  default     = "main"
}

variable "rancher_chart_version" {
  description = "Rancher Chart/버전 (targetRevision)"
  type        = string
  default     = "2.10.10"
}

variable "rancher_bootstrap_password" {
  description = "Rancher 초기 bootstrap 비밀번호 (필수: enable_rancher_app=true 일 때)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "rancher_ingress_class_name" {
  description = "Rancher IngressClass 이름"
  type        = string
  default     = "nginx"
}

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
