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

  default = {
    "public-a" = {
      cidr   = "10.0.201.0/24"
      az     = "ap-northeast-2a"
      tier   = "public"
      public = true
    }
    "public-c" = {
      cidr   = "10.0.202.0/24"
      az     = "ap-northeast-2c"
      tier   = "public"
      public = true
    }
    "k8s-dp-a" = {
      cidr   = "10.0.21.0/24"
      az     = "ap-northeast-2a"
      tier   = "k8s_dp"
      public = false
    }
    "k8s-dp-c" = {
      cidr   = "10.0.22.0/24"
      az     = "ap-northeast-2c"
      tier   = "k8s_dp"
      public = false
    }
    "k8s-cp-a" = {
      cidr   = "10.0.11.0/24"
      az     = "ap-northeast-2a"
      tier   = "k8s_cp"
      public = false
    }
    "k8s-cp-c" = {
      cidr   = "10.0.12.0/24"
      az     = "ap-northeast-2c"
      tier   = "k8s_cp"
      public = false
    }
    "db-a" = {
      cidr   = "10.0.1.0/24"
      az     = "ap-northeast-2a"
      tier   = "db"
      public = false
    }
    "db-c" = {
      cidr   = "10.0.2.0/24"
      az     = "ap-northeast-2c"
      tier   = "db"
      public = false
    }

    # 공통 private 서브넷 (SSM 기반 Bastion/Harbor 등 공용 인프라 워크로드)
    "common-private-a" = {
      cidr   = "10.0.101.0/24"
      az     = "ap-northeast-2a"
      tier   = "common"
      public = false
    }
    "common-private-c" = {
      cidr   = "10.0.102.0/24"
      az     = "ap-northeast-2c"
      tier   = "common"
      public = false
    }
  }
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
