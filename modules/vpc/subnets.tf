# ==============================================================================
# Subnets & Routing Configuration
# ==============================================================================

locals {
  # Subnet naming prefix: dev-meta-snet
  subnet_name_prefix = "${local.base_prefix}-snet"

  # Subnet offsets (3rd octet for /24 subnets in /16 VPC)
  default_subnets = {
    "common-pub-a" = { az = "ap-northeast-2a", tier = "public", public = true, netnum = 201 }
    "common-pub-c" = { az = "ap-northeast-2c", tier = "public", public = true, netnum = 202 }
    "db-pri-a"     = { az = "ap-northeast-2a", tier = "db", public = false, netnum = 1 }
    "db-pri-c"     = { az = "ap-northeast-2c", tier = "db", public = false, netnum = 2 }
    "k8s-cp-pri-a" = { az = "ap-northeast-2a", tier = "k8s_cp", public = false, netnum = 11 }
    "k8s-cp-pri-c" = { az = "ap-northeast-2c", tier = "k8s_cp", public = false, netnum = 12 }
    "k8s-dp-pri-a" = { az = "ap-northeast-2a", tier = "k8s_dp", public = false, netnum = 21 }
    "k8s-dp-pri-c" = { az = "ap-northeast-2c", tier = "k8s_dp", public = false, netnum = 22 }
    "common-pri-a" = { az = "ap-northeast-2a", tier = "common", public = false, netnum = 101 }
    "common-pri-c" = { az = "ap-northeast-2c", tier = "common", public = false, netnum = 102 }
  }

  calculated_subnets = {
    for k, v in local.default_subnets : k => {
      cidr   = cidrsubnet(var.vpc_cidr, 8, v.netnum)
      az     = v.az
      tier   = v.tier
      public = v.public
    }
  }

  final_subnets = var.subnets != null ? var.subnets : local.calculated_subnets

  # Helper for Gateway logic (Picking one public subnet per AZ)
  public_subnet_id_by_az = {
    for az in var.azs :
    az => [for k, v in local.final_subnets : aws_subnet.this[k].id if v.az == az && v.tier == "public"][0]
  }
}

# ------------------------------------------------------------------------------
# Subnets
# ------------------------------------------------------------------------------
resource "aws_subnet" "this" {
  for_each = local.final_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = each.value.public

  tags = merge(local.tags, {
    Name = "${local.subnet_name_prefix}-${each.key}"
    Tier = each.value.tier
    AZ   = each.value.az
    },
    var.kubernetes_cluster_name != "" ? { "kubernetes.io/cluster/${var.kubernetes_cluster_name}" = "shared" } : {},
    each.value.public ? { "kubernetes.io/role/elb" = "1" } : { "kubernetes.io/role/internal-elb" = "1" }
  )
}

# ------------------------------------------------------------------------------
# Route Tables
# ------------------------------------------------------------------------------

# Public Route Table (Shared)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.tags, {
    Name = "${local.base_prefix}-rt-public"
    Tier = "public"
  })
}

# Private Route Tables (Per AZ)
resource "aws_route_table" "private" {
  for_each = toset(var.azs)
  vpc_id   = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.base_prefix}-rt-private-${each.key}"
    Tier = "private"
    AZ   = each.key
  })
}

# DB Route Tables (Per AZ)
resource "aws_route_table" "db" {
  for_each = toset(var.azs)
  vpc_id   = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.base_prefix}-rt-db-${each.key}"
    Tier = "db"
    AZ   = each.key
  })
}

# ------------------------------------------------------------------------------
# Route Table Associations
# ------------------------------------------------------------------------------

locals {
  # Group Subnet Keys by Type for Association
  public_subnet_keys = [for k, v in local.final_subnets : k if v.tier == "public"]

  private_subnet_keys_by_az = {
    for az in var.azs :
    az => [for k, v in local.final_subnets : k if v.az == az && v.public == false && v.tier != "db"]
  }

  db_subnet_keys_by_az = {
    for az in var.azs :
    az => [for k, v in local.final_subnets : k if v.az == az && v.tier == "db"]
  }

  # Flatten for Association Resources
  private_assoc_map = merge([
    for az, keys in local.private_subnet_keys_by_az : {
      for k in keys : "${az}-${k}" => { az = az, subnet_key = k }
    }
  ]...)

  db_assoc_map = merge([
    for az, keys in local.db_subnet_keys_by_az : {
      for k in keys : "${az}-${k}" => { az = az, subnet_key = k }
    }
  ]...)
}

resource "aws_route_table_association" "public" {
  for_each       = toset(local.public_subnet_keys)
  subnet_id      = aws_subnet.this[each.value].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  for_each       = local.private_assoc_map
  subnet_id      = aws_subnet.this[each.value.subnet_key].id
  route_table_id = aws_route_table.private[each.value.az].id
}

resource "aws_route_table_association" "db" {
  for_each       = local.db_assoc_map
  subnet_id      = aws_subnet.this[each.value.subnet_key].id
  route_table_id = aws_route_table.db[each.value.az].id
}
