################################################################################
# Required Variables
################################################################################

variable "project" {
  description = "프로젝트/조직 식별자"
  type        = string
}

variable "env" {
  description = "환경 (dev/staging/prod)"
  type        = string
}

variable "domain" {
  description = "기본 도메인 (예: example.com)"
  type        = string
}

variable "bootstrap_password" {
  description = "Rancher 초기 관리자 비밀번호"
  type        = string
  sensitive   = true
}

################################################################################
# Rancher Configuration
################################################################################

variable "rancher_hostname" {
  description = "Rancher hostname (전체 FQDN). null이면 rancher_subdomain.domain 사용"
  type        = string
  default     = null
}

variable "rancher_subdomain" {
  description = "Rancher 서브도메인 (예: rancher → rancher.example.com)"
  type        = string
  default     = "rancher"
}

variable "rancher_version" {
  description = "Rancher Helm 차트 버전. RKE2 v1.31 호환: Rancher 2.10.x(Stable)"
  type        = string
  default     = "2.10.10"

  # Rancher 2.10.x: K8s 1.28~1.31 지원
  # Rancher 2.11.x: K8s 1.30~1.32 지원
  # Rancher 2.12.x: K8s 1.31~1.33 지원
  validation {
    condition     = can(regex("^2\\.(10|1[1-9]|[2-9][0-9])\\.[0-9]+.*$", var.rancher_version))
    error_message = "rancher_version must be 2.10.x or newer. Example: 2.10.10"
  }
}


variable "rancher_helm_repo" {
  description = "Rancher Helm 저장소 URL (stable/latest/alpha)"
  type        = string
  default     = "https://releases.rancher.com/server-charts/stable"
  validation {
    condition = contains([
      "https://releases.rancher.com/server-charts/stable",
      "https://releases.rancher.com/server-charts/latest",
      "https://releases.rancher.com/server-charts/alpha"
    ], var.rancher_helm_repo)
    error_message = "rancher_helm_repo must be stable, latest, or alpha"
  }
}

variable "rancher_replicas" {
  description = "Rancher 레플리카 수 (HA는 3 권장)"
  type        = number
  default     = 3
}

variable "rancher_resources" {
  description = "Rancher Pod 리소스 설정"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "250m"
      memory = "512Mi"
    }
    limits = {
      cpu    = "1000m"
      memory = "2Gi"
    }
  }
}

################################################################################
# TLS/Certificate Configuration
################################################################################

variable "tls_source" {
  description = "TLS 인증서 소스: rancher (자체 CA), letsEncrypt, secret (외부 인증서), external (NLB/ALB에서 TLS 종료)"
  type        = string
  default     = "external"
  validation {
    condition     = contains(["rancher", "letsEncrypt", "secret", "external"], var.tls_source)
    error_message = "tls_source must be one of: rancher, letsEncrypt, secret, external"
  }
}

variable "external_tls_termination" {
  description = <<-EOT
    외부 로드밸런서(NLB/ALB)에서 TLS를 종료할 때 true로 설정.
    true로 설정하면:
    - Rancher Ingress는 HTTP로 설정됨
    - cert-manager 설치는 선택적 (기본: 설치 안함)
    - 실제 TLS는 AWS NLB + ACM에서 처리
  EOT
  type        = bool
  default     = true
}

variable "letsencrypt_email" {
  description = "Let's Encrypt 이메일 (tls_source가 letsEncrypt일 때 필수)"
  type        = string
  default     = ""
}

variable "letsencrypt_environment" {
  description = "Let's Encrypt 환경 (production/staging)"
  type        = string
  default     = "staging"
  validation {
    condition     = contains(["production", "staging"], var.letsencrypt_environment)
    error_message = "letsencrypt_environment must be production or staging"
  }
}

variable "private_ca" {
  description = "Private CA 사용 여부 (secret TLS 소스와 함께 사용)"
  type        = bool
  default     = false
}

variable "create_cluster_issuer" {
  description = "ClusterIssuer 리소스 생성 여부"
  type        = bool
  default     = false
}

variable "skip_cert_manager" {
  description = "cert-manager 설치 건너뛰기 (external TLS termination 사용 시 true 권장)"
  type        = bool
  default     = true
}

################################################################################
# cert-manager Configuration
################################################################################

variable "cert_manager_version" {
  description = "cert-manager Helm 차트 버전"
  type        = string
  default     = "v1.14.5"  # 2024년 안정 버전
}

variable "cert_manager_resources" {
  description = "cert-manager Pod 리소스 설정"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "50m"
      memory = "64Mi"
    }
    limits = {
      cpu    = "200m"
      memory = "256Mi"
    }
  }
}

################################################################################
# Ingress Configuration
################################################################################

variable "ingress_class_name" {
  description = "Ingress Controller 클래스명 (nginx, traefik 등)"
  type        = string
  default     = "nginx"  # RKE2 기본 Ingress Controller
}

################################################################################
# Private Registry (Harbor) Configuration
################################################################################

variable "private_registry" {
  description = "Private Registry 주소 (예: harbor.example.com:5000). null이면 공용 레지스트리 사용"
  type        = string
  default     = null
}

variable "use_bundled_system_chart" {
  description = "Bundled system chart 사용 (Air-gap 환경)"
  type        = bool
  default     = false
}

################################################################################
# Network Configuration
################################################################################

variable "dns_server" {
  description = "DNS 서버 주소 (cert-manager Pod DNS 설정)"
  type        = string
  default     = "169.254.169.253"  # AWS VPC DNS
}

################################################################################
# Audit Log Configuration
################################################################################

variable "enable_audit_log" {
  description = "Rancher Audit Log 활성화"
  type        = bool
  default     = false
}

variable "audit_log_level" {
  description = "Audit Log 레벨 (0-3)"
  type        = number
  default     = 1
  validation {
    condition     = var.audit_log_level >= 0 && var.audit_log_level <= 3
    error_message = "audit_log_level must be between 0 and 3"
  }
}

variable "audit_log_destination" {
  description = "Audit Log 저장 위치 (sidecar, hostPath)"
  type        = string
  default     = "sidecar"
  validation {
    condition     = contains(["sidecar", "hostPath"], var.audit_log_destination)
    error_message = "audit_log_destination must be sidecar or hostPath"
  }
}

################################################################################
# Extra Configuration
################################################################################

variable "extra_env" {
  description = "추가 환경변수 (Proxy 설정 등)"
  type        = map(string)
  default     = {}
}

variable "labels" {
  description = "추가 라벨"
  type        = map(string)
  default     = {}
}
