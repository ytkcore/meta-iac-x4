# ==============================================================================
# Gateways & Endpoints Configuration
# ==============================================================================

# ------------------------------------------------------------------------------
# NAT Gateway
# ------------------------------------------------------------------------------
locals {
  # Create NAT per AZ if enable_nat is true
  nat_azs = var.enable_nat ? toset(var.azs) : toset([])
}

resource "aws_eip" "nat" {
  for_each = local.nat_azs
  domain   = "vpc"

  tags = merge(local.tags, {
    Name = "${local.base_prefix}-eip-nat-${each.key}"
  })
}

resource "aws_nat_gateway" "this" {
  for_each = local.nat_azs

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = local.public_subnet_id_by_az[each.key]

  tags = merge(local.tags, {
    Name = "${local.base_prefix}-ngw-${each.key}"
  })

  depends_on = [aws_internet_gateway.this]
}

# ------------------------------------------------------------------------------
# Routes to NAT
# ------------------------------------------------------------------------------
resource "aws_route" "private_nat" {
  for_each = local.nat_azs

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.key].id
}

resource "aws_route" "db_nat" {
  for_each = (var.enable_nat && var.enable_nat_for_db) ? toset(var.azs) : toset([])

  route_table_id         = aws_route_table.db[each.value].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.value].id
}

# ------------------------------------------------------------------------------
# VPC Endpoints (Gateway)
# ------------------------------------------------------------------------------
locals {
  gateway_services_set = var.enable_gateway_endpoints ? toset(var.gateway_services) : toset([])

  # Collect all route tables that need endpoint access
  endpoint_route_table_ids = concat(
    [aws_route_table.public.id],
    values(aws_route_table.private)[*].id,
    values(aws_route_table.db)[*].id
  )
}

resource "aws_vpc_endpoint" "gateway" {
  for_each = local.gateway_services_set

  vpc_id            = aws_vpc.this.id
  vpc_endpoint_type = "Gateway"
  service_name      = "com.amazonaws.${var.region}.${each.value}"
  route_table_ids   = local.endpoint_route_table_ids

  tags = merge(local.tags, {
    Name    = "${local.base_prefix}-vpce-gw-${each.value}"
    Type    = "gateway"
    Service = each.value
  })
}
# ------------------------------------------------------------------------------
# VPC Endpoints (Interface) - Integrated for Foundation Management
# ------------------------------------------------------------------------------

resource "aws_security_group" "vpce" {
  count       = var.enable_interface_endpoints ? 1 : 0
  name        = "${local.base_prefix}-vpce-sg"
  description = "Security group for VPC Endpoints (HTTPS)"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${local.base_prefix}-vpce-sg"
  })
}

locals {
  # Get actual subnet IDs for interface endpoints
  interface_subnet_ids = flatten([
    for t in var.interface_subnet_tiers : [
      for k, v in local.final_subnets : aws_subnet.this[k].id if v.tier == t
    ]
  ])
}

module "endpoints" {
  source = "../vpc-endpoints"
  count  = var.enable_interface_endpoints ? 1 : 0

  name                       = "${local.base_prefix}-mgmt"
  region                     = var.region
  vpc_id                     = aws_vpc.this.id
  enable_interface_endpoints = true
  interface_services         = var.interface_services
  interface_subnet_ids       = local.interface_subnet_ids
  security_group_ids         = [aws_security_group.vpce[0].id]

  tags = local.tags
}
