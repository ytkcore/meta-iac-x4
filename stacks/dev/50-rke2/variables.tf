variable "env" {
  description = "환경 (dev/prod)"
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

# env.tfvars에서 공통으로 주입될 수 있는 값들(backend 관련)
variable "state_bucket" {
  description = "Terraform remote state S3 bucket"
  type        = string
  default     = null
}

variable "state_region" {
  description = "Terraform remote state S3 region"
  type        = string
  default     = null
}

variable "state_key_prefix" {
  description = "Terraform remote state key prefix"
  type        = string
  default     = null
}

variable "azs" {
  description = "Multi-AZ 사용 목록 (예: [\"ap-northeast-2a\",\"ap-northeast-2c\"]). env.tfvars에서 공통으로 주입됩니다."
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

# tags 제거 (locals 자동 생성)
# name 제거 (locals 자동 생성)

variable "control_plane_count" {
  description = "Control Plane 노드 수"
  type        = number
  default     = 3
}

variable "worker_count" {
  description = "Worker(Data Plane) 노드 수"
  type        = number
  default     = 4
}

variable "instance_type" {
  description = "기본 인스턴스 스펙(개발망): t3.large"
  type        = string
  default     = "t3.large"
}

variable "root_volume_type" {
  description = "Root EBS 타입"
  type        = string
  default     = "gp3"
}

variable "root_volume_size_gb" {
  description = "Root EBS 크기(GB) - 개발망 최소 사양"
  type        = number
  default     = 30
}

variable "enable_internal_nlb" {
  description = "내부 NLB 생성 여부 (6443/9345)"
  type        = bool
  default     = true
}

variable "rke2_version" {
  description = "RKE2 버전. Rancher 2.10.x(Stable) 호환: v1.28~v1.31"
  type        = string
  default     = "v1.31.6+rke2r1" # Rancher 2.10.x (stable) 호환 최신
}

variable "rke2_token" {
  description = "RKE2 조인 토큰(선택). 비워두면 자동 생성."
  type        = string
  default     = null
  sensitive   = true
}

variable "extra_policy_arns" {
  description = "노드 IAM Role에 추가로 부착할 Managed Policy ARN 목록(선택)"
  type        = list(string)
  default     = []
}

variable "ami_id" {
  description = "원하는 AMI ID(선택). 비워두면 Amazon Linux 2023 최신 AMI 사용."
  type        = string
  default     = null
}

variable "os_family" {
  description = "노드 OS 선택 (al2023 | ubuntu2204)"
  type        = string
  default     = "al2023"
}

##############################
# Harbor Registry (Optional)
##############################
variable "use_harbor" {
  description = "Harbor 레지스트리 사용 여부 (false면 공용 레지스트리 사용)"
  type        = bool
  default     = false
}

variable "auto_use_harbor_if_state_exists" {
  description = "45-harbor.tfstate가 존재하면 Harbor 연동을 자동 활성화"
  type        = bool
  default     = true
}


variable "disable_default_registry_fallback" {
  description = "기본 레지스트리(docker.io 등) fallback 비활성화 (폐쇄망 환경)"
  type        = bool
  # Harbor 미러/프록시 캐시를 강제하여 외부 egress 통제를 일관되게 유지합니다.
  default = true
}

variable "harbor_auth_enabled" {
  description = "Harbor 인증 사용 여부 (private project 접근 시 필요)"
  type        = bool
  default     = false
}

variable "harbor_username" {
  description = "Harbor 인증 사용자명 (harbor_auth_enabled=true 시 필요)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "harbor_password" {
  description = "Harbor 인증 비밀번호 (harbor_auth_enabled=true 시 필요)"
  type        = string
  default     = ""
  sensitive   = true
}

##############################
# Public Ingress NLB (Optional)
##############################
variable "enable_public_ingress_nlb" {
  description = "Public NLB 생성 여부 (Ingress Controller용 80/443)"
  type        = bool
  default     = false
}

variable "enable_public_ingress_http_listener" {
  description = "Public Ingress NLB에서 HTTP(80) listener 생성 여부"
  type        = bool
  default     = false
}


variable "ingress_http_nodeport" {
  description = "Nginx Ingress Controller HTTP NodePort (기본: 30080)"
  type        = number
  default     = 30080
}

variable "ingress_https_nodeport" {
  description = "Nginx Ingress Controller HTTPS NodePort (기본: 30443)"
  type        = number
  default     = 30443
}

##############################
# ACM TLS Termination (Optional)
##############################
variable "enable_acm_tls_termination" {
  description = "NLB 레벨에서 AWS ACM TLS 종료 활성화"
  type        = bool
  default     = true
}

variable "acm_certificate_arn" {
  description = "AWS ACM 인증서 ARN (enable_acm_tls_termination=true 일 때 필수)"
  type        = string
  default     = null
}



variable "base_domain" {
  description = "ACM 자동 조회용 루트 도메인 (예: example.com). 지정 시 '*.<base_domain>' 인증서를 조회합니다."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9.-]+$", var.base_domain))
    error_message = "도메인 형식은 소문자, 숫자, 점(.), 하이픈(-)만 허용됩니다."
  }
}

variable "acm_cert_domain" {
  description = "ACM 자동 조회 도메인(하버 방식). 예: '*.dev.example.com'. 지정 시 base_domain보다 우선합니다."
  type        = string
  default     = null
}

# 호환용(이전 명칭)
variable "acm_cert_search_domain" {
  description = "ACM 자동 조회 도메인(호환용). acm_cert_domain이 없을 때 사용됩니다."
  type        = string
  default     = null
}
variable "acm_ssl_policy" {
  description = "NLB TLS 리스너에 적용할 SSL 정책"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}
