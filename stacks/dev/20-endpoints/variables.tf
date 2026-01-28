variable "region" {
  type = string
}
variable "env" {
  type = string
}
variable "project" {
  type = string
}
variable "name" {
  type = string
}
variable "tags" {
  type = map(string)
}

variable "state_bucket" {
  type = string
}

# place interface endpoints in these subnet tiers
variable "interface_subnet_tiers" {
  type    = list(string)
  default = ["k8s_cp", "k8s_dp", "db", "common"]
}

# attach S3 gateway endpoint to which route table tiers
variable "enable_interface_endpoints" {
  type        = bool
  description = "Interface Endpoint 생성 여부. 기본값 false(비활성화)."
  default     = false
}

variable "interface_services" {
  type        = list(string)
  description = "Interface endpoint 서비스 목록 (예: [\"ecr.api\",\"ecr.dkr\",\"logs\",\"sts\"]). 빈 배열이면 생성되지 않습니다."
  default     = []
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

variable "azs" {
  type        = list(string)
  description = "Multi-AZ 사용 목록 (예: [\"ap-northeast-2a\",\"ap-northeast-2c\"]). env.tfvars에서 공통으로 주입됩니다."
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "vpce_security_group_id" {
  type        = string
  description = "Interface VPC Endpoint용 SG ID를 외부에서 주입할 때 사용합니다. null이면 endpoints 스택에서 기본 SG를 생성합니다."
  default     = null
}

