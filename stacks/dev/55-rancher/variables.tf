################################################################################
# 55-rancher Stack Variables (DEV)
#
# 목표:
# - 스택에서는 DNS(FQDN 구성에 필요한 domain) + 최소 운영 입력만 받습니다.
# - Rancher/Helm 상세 설정(TLS mode, cert-manager 등)은 modules/rancher의 default를 사용합니다.
#
# 전제:
# - Ingress Service 앞단 Public NLB에서 ACM으로 TLS 종료 (External TLS Termination)
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
  description = "Multi-AZ 사용 목록"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

################################################################################
# Kubernetes Connection (kubeconfig 기반)
################################################################################

variable "kubeconfig_path" {
  description = "kubeconfig 파일 경로"
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = "kubeconfig context 이름 (null이면 current-context 사용)"
  type        = string
  default     = null
}

################################################################################
# DNS / Access (스택 입력 최소)
################################################################################

variable "domain" {
  description = "기본 도메인 (예: example.com). 모듈 기본값으로 rancher.<domain>을 구성"
  type        = string
}

variable "bootstrap_password" {
  description = "Rancher 초기 관리자 비밀번호 (권장: TF_VAR_bootstrap_password로 주입)"
  type        = string
  sensitive   = true
}

################################################################################
# Optional: Private Registry (Harbor 연동)
################################################################################

variable "use_harbor_registry" {
  description = "45-harbor 스택의 Harbor 레지스트리 사용 여부"
  type        = bool
  default     = false
}

variable "private_registry" {
  description = "Harbor 미사용 시 별도 Private Registry 주소 (예: registry.example.com:5000). null이면 공용 레지스트리 사용"
  type        = string
  default     = null
}
