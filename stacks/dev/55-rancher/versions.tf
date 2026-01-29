# =============================================================================
# [Centralized Version Control]
# 이 파일은 각 스택의 'versions_gen.tf' 심볼릭 링크를 통해 참조됩니다.
# =============================================================================

#terraform {
#  # Terraform Core 버전 제약 (예: 1.0 이상)
#  required_version = ">= 1.0"
#
#  required_providers {
#    aws = {
#      source = "hashicorp/aws"
#      # AWS Provider 버전 고정 (Breaking Change 방지)
#      version = ">= 5.0"
#    }
#
#    # 필요시 추가 (예: random)
#    random = {
#      source  = "hashicorp/random"
#      version = ">= 3.0"
#    }
#  }
#}

terraform {
  required_version = ">= 1.4.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.25.0"
    }
    helm = {
      source = "hashicorp/helm"
      # [수정] v3.0.0 이상은 kubernetes 블록을 지원하지 않으므로 v2.x로 고정
      version = ">= 2.12.0, < 3.0.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.10.0"
    }
  }
}
