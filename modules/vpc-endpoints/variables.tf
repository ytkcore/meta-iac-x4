variable "name" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

# Interface endpoints (옵션)
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

variable "interface_subnet_ids" {
  type        = list(string)
  description = "Interface endpoint를 배치할 Subnet ID 목록(일반적으로 private tiers)."
  default     = []
}

variable "security_group_ids" {
  type        = list(string)
  description = "Interface endpoint에 부착할 SG ID 목록."
  default     = []
}

variable "private_dns_enabled" {
  type        = bool
  description = "Private DNS 활성화 여부."
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "공통 태그"
  default     = {}
}
