# ==============================================================================
# Unified Network Module
#
# Description:
#   - Defines the core network infrastructure (VPC, Subnets, Routing, NAT/IGW).
#   - Supports dynamic subnet calculation based on VPC CIDR.
#
# Maintainer: DevOps Team
# ==============================================================================

locals {
  # ------------------------------------------------------------------------------
  # Naming Convention (Standardized)
  # Format: {env}-{project}-{resource}-{suffix} for Network Shared Resources
  # ------------------------------------------------------------------------------
  base_prefix = "${var.env}-${var.project}"

  tags = {
    ManagedBy   = "terraform"
    Project     = var.project
    Environment = var.env
  }
}

# ------------------------------------------------------------------------------
# VPC & Gateway
# ------------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, {
    Name = "${local.base_prefix}-vpc" # dev-meta-vpc
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.base_prefix}-igw" # dev-meta-igw
  })
}
