# -----------------------------------------------------------------------------
# Subnets 모듈
# - 입력(var.subnets)으로 정의된 서브넷들을 일괄 생성합니다.
# - 서브넷은 일반적으로 '초기 1회' 셋업 후 변경 빈도가 낮으므로,
#   안정적인 식별자(key)로 관리(예: pub-a, priv-c 등)하는 것을 권장합니다.
# -----------------------------------------------------------------------------

resource "aws_subnet" "this" {
  for_each = var.subnets

  vpc_id                  = var.vpc_id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = try(each.value.public, false)

  tags = merge(var.tags, try(each.value.tags, {}), {
    Name = "${var.name}-${each.key}"
    Tier = each.value.tier
    AZ   = each.value.az
  })
}
