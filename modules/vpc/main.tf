# -----------------------------------------------------------------------------
# VPC 모듈
# - 네트워크의 최상위 경계(VPC)를 생성합니다.
# - DNS 지원/호스트네임 활성화 여부를 설정합니다.
# - 조직 표준 태그(var.tags)와 리소스별 Name 태그를 병합해 적용합니다.
# -----------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = merge(var.tags, { Name = var.name })
}
