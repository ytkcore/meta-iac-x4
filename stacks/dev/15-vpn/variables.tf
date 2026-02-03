variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "env" {
  type = string
}

variable "project" {
  type = string
}

# Remote state settings
variable "state_bucket" {
  type        = string
  description = "Remote state S3 bucket"
  default     = null
}

variable "state_region" {
  type        = string
  description = "Remote state region"
  default     = null
}

variable "state_key_prefix" {
  type        = string
  description = "Remote state key prefix"
  default     = null
}

# VPN 설정
variable "vpn_cidr_block" {
  type        = string
  description = "VPN 클라이언트에 할당할 CIDR 블록 (VPC CIDR과 겹치면 안됨)"
  default     = "10.100.0.0/16"
}

variable "vpn_split_tunnel" {
  type        = bool
  description = "Split Tunnel 활성화 (true: VPC만 VPN 경유, false: 모든 트래픽 VPN 경유)"
  default     = true
}

variable "vpn_session_timeout_hours" {
  type        = number
  description = "VPN 세션 타임아웃 (시간)"
  default     = 8
}

variable "vpn_log_retention_days" {
  type        = number
  description = "VPN 연결 로그 보존 기간 (일)"
  default     = 30
}

variable "vpn_subnet_key" {
  type        = string
  description = "VPN을 연결할 Private 서브넷 키"
  default     = "common-pri-a"
}

variable "vpn_dns_servers" {
  type        = list(string)
  description = "VPN 클라이언트에 전달할 DNS 서버 (비어있으면 VPC DNS 사용)"
  default     = []
}

# 인증서 관련
variable "vpn_server_cert_arn" {
  type        = string
  description = "기존 Server 인증서 ARN (없으면 새로 생성)"
  default     = null
}

variable "vpn_client_cert_arn" {
  type        = string
  description = "기존 Client Root 인증서 ARN (없으면 새로 생성)"
  default     = null
}

variable "vpn_cert_validity_days" {
  type        = number
  description = "Self-signed 인증서 유효 기간 (일)"
  default     = 365
}

# 공용 변수 (호환성)
variable "azs" {
  type    = list(string)
  default = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "base_domain" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}

# env.tfvars 호환성을 위한 더미 변수
variable "target_bucket_name" {
  type    = string
  default = ""
}

variable "longhorn_backup_bucket" {
  type    = string
  default = ""
}

variable "enable_gitops_apps" {
  type    = bool
  default = false
}

variable "gitops_apps_path" {
  type    = string
  default = ""
}

variable "gitops_repo_url" {
  type    = string
  default = ""
}

variable "gitops_ssh_key_path" {
  type    = string
  default = ""
}
