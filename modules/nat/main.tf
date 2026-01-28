# -----------------------------------------------------------------------------
# NAT 모듈
# - 프라이빗/DB 서브넷의 아웃바운드(인터넷 egress)를 위해 NAT Gateway를 생성합니다.
# - AZ별 NAT 구성은 비용은 증가하지만 장애 격리를 개선합니다.
# - depends_on은 리소스 간 암묵적 의존성이 부족할 때 '명시적 순서'를 강제하는 용도로 사용합니다.
# -----------------------------------------------------------------------------

resource "aws_eip" "nat" {
  for_each = var.public_subnet_id_by_az
  domain   = "vpc"
  tags     = merge(var.tags, { Name = "${var.name}-eip-nat-${each.key}" })
}

resource "aws_nat_gateway" "this" {
  for_each      = var.public_subnet_id_by_az
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = each.value
  tags          = merge(var.tags, { Name = "${var.name}-nat-${each.key}", AZ = each.key })
}
