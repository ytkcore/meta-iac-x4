# -----------------------------------------------------------------------------
# VPC Endpoints 모듈 (Interface 전용)
# - Interface Endpoint를 '옵션'으로 생성합니다. (기본 OFF)
# - Gateway Endpoint(S3/DynamoDB)는 네트워크 기반 구성으로 보고 00-network에 통합되어 있습니다.
# - 필요할 때만 stacks/*/20-endpoints에서 enable_interface_endpoints=true로 활성화하세요.
# -----------------------------------------------------------------------------

# VPC Interface Endpoints (optional)
# - 기본값: 비활성화(enable_interface_endpoints=false)
# - 활성화 시 interface_services에 나열된 서비스에 대해 Interface Endpoint를 생성합니다.

locals {
  interface_enabled = var.enable_interface_endpoints && length(var.interface_services) > 0
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = local.interface_enabled ? toset(var.interface_services) : toset([])
  vpc_id              = var.vpc_id
  vpc_endpoint_type   = "Interface"
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  subnet_ids          = var.interface_subnet_ids
  security_group_ids  = var.security_group_ids
  private_dns_enabled = var.private_dns_enabled

  tags = merge(var.tags, {
    Name    = "${var.name}-vpce-if-${replace(each.value, ".", "-")}"
    Type    = "interface"
    Service = each.value
  })
}
