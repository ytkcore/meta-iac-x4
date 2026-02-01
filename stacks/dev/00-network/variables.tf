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

# name 제거 (locals에서 생성)
# tags 제거 (locals에서 생성 혹은 default 처리)

# Shared remote state settings used by downstream stacks via terraform_remote_state.
# (This stack itself does not consume remote state, but it declares these variables
# so stacks/<env>/env.tfvars can be reused across all stacks.)
# -----------------------------
# Network topology knobs
# -----------------------------
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "enable_nat" {
  description = "If true, create NAT gateways and private route default via NAT."
  type        = bool
  default     = true
}
variable "enable_nat_for_db" {
  description = "If true, add default route via NAT to DB route tables (for outbound access / SSM)."
  type        = bool
  default     = true
}



# Gateway VPC Endpoints (기본: S3 + DynamoDB)
variable "enable_gateway_endpoints" {
  type        = bool
  description = "Gateway VPC Endpoint 생성 여부. 기본 true."
  default     = true
}

variable "gateway_services" {
  type        = list(string)
  description = "Gateway endpoint 서비스 목록. 기본값은 [\"s3\",\"dynamodb\"] 입니다."
  default     = ["s3", "dynamodb"]
}
variable "subnets" {
  description = "Subnet definitions keyed by name."
  type = map(object({
    cidr   = string
    az     = string
    tier   = string # public | common | k8s_cp | k8s_dp | db
    public = bool
  }))

  default = null
}

variable "state_bucket" {
  type        = string
  description = "Remote state S3 bucket (used by Makefile/terraform init backend-config). Kept here to avoid tfvars undeclared warnings."
  default     = null
}

variable "state_region" {
  type        = string
  description = "Remote state region (used by Makefile/terraform init backend-config). Kept here to avoid tfvars undeclared warnings."
  default     = null
}

variable "state_key_prefix" {
  type        = string
  description = "Remote state key prefix (used by Makefile/terraform init backend-config). Kept here to avoid tfvars undeclared warnings."
  default     = null
}

# [NEW] Optional: user defined base_domain (not used in network but to avoid undeclared variable error)
variable "base_domain" {
  type        = string
  description = "Base domain (not used in network stack but present in global env.tfvars)"
  default     = null

  validation {
    condition     = can(regex("^[a-z0-9.-]+$", var.base_domain))
    error_message = "도메인 형식은 소문자, 숫자, 점(.), 하이픈(-)만 허용됩니다."
  }
}
