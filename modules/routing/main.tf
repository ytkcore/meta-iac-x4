# -----------------------------------------------------------------------------
# Routing 모듈
# - 퍼블릭/프라이빗/DB 라우트 테이블을 생성하고,
#   서브넷과의 연결(association)을 수행합니다.
# - Terraform의 for_each 키는 plan 시점에 '확정'되어야 합니다.
#   따라서 apply 시점에만 결정되는 값(unknown)을 키로 사용하지 않도록,
#   항상 '정적 키(map key)' 기반으로 association을 구성합니다.
# -----------------------------------------------------------------------------

# Public route table (shared)
resource "aws_route_table" "public" {
  vpc_id = var.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = var.igw_id
  }

  tags = merge(var.tags, { Name = "${var.name}-rt-public", Tier = "public" })
}


locals {
  # for_each keys must be fully known at plan time. Subnet IDs are unknown until apply,
  # so we use stable index-based keys and keep apply-time IDs in values.
  public_assoc = { for idx, sid in var.public_subnet_ids : tostring(idx) => sid }
}

resource "aws_route_table_association" "public" {
  for_each       = local.public_assoc
  subnet_id      = each.value
  route_table_id = aws_route_table.public.id
}

# Private route tables (per AZ)
resource "aws_route_table" "private" {
  for_each = var.private_subnet_ids_by_az
  vpc_id   = var.vpc_id

  dynamic "route" {
    for_each = (var.enable_nat && contains(keys(var.nat_gateway_id_by_az), each.key)) ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = var.nat_gateway_id_by_az[each.key]
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-rt-private-${each.key}", Tier = "private", AZ = each.key })
}

locals {
  # IMPORTANT:
  # for_each keys must be fully known at plan time. Subnet IDs are unknown until apply,
  # so we use index-based stable keys (<az>:<index>) and keep apply-time IDs in values.
  private_assoc = merge([
    for az, subnet_ids in var.private_subnet_ids_by_az : {
      for idx, sid in subnet_ids :
      "${az}:${idx}" => { az = az, subnet_id = sid }
    }
  ]...)
}

resource "aws_route_table_association" "private" {
  for_each       = local.private_assoc
  subnet_id      = each.value.subnet_id
  route_table_id = aws_route_table.private[each.value.az].id
}

# DB route tables (per AZ, local-only)
resource "aws_route_table" "db" {
  for_each = var.db_subnet_ids_by_az
  vpc_id   = var.vpc_id

  dynamic "route" {
    for_each = var.enable_nat && var.enable_nat_for_db && contains(keys(var.nat_gateway_id_by_az), each.key) ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = var.nat_gateway_id_by_az[each.key]
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-rt-db-${each.key}", Tier = "db", AZ = each.key })
}

locals {
  # IMPORTANT:
  # for_each keys must be fully known at plan time. Subnet IDs are unknown until apply,
  # so we use index-based stable keys (<az>:<index>) and keep apply-time IDs in values.
  db_assoc = merge([
    for az, subnet_ids in var.db_subnet_ids_by_az : {
      for idx, sid in subnet_ids :
      "${az}:${idx}" => { az = az, subnet_id = sid }
    }
  ]...)
}

resource "aws_route_table_association" "db" {
  for_each       = local.db_assoc
  subnet_id      = each.value.subnet_id
  route_table_id = aws_route_table.db[each.value.az].id
}
