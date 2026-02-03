# =============================================================================
# Native Terraform Import Blocks - 00-network
# =============================================================================

# [USAGE]
# 1. Fill in the 'id' fields with actual AWS resource IDs.
# 2. Run 'make plan STACK=00-network' to verify.
# 3. Run 'make apply STACK=00-network' to commit the imports to state.

/*
# VPC
import {
  to = module.network.aws_vpc.this
  id = "VPC_ID"
}

# Internet Gateway
import {
  to = module.network.aws_internet_gateway.this
  id = "IGW_ID"
}

# Subnets
import {
  to = module.network.aws_subnet.this["common-pub-a"]
  id = "SUBNET_ID"
}

import {
  to = module.network.aws_subnet.this["common-pub-c"]
  id = "SUBNET_ID"
}

import {
  to = module.network.aws_subnet.this["db-pri-a"]
  id = "SUBNET_ID"
}

import {
  to = module.network.aws_subnet.this["db-pri-c"]
  id = "SUBNET_ID"
}

import {
  to = module.network.aws_subnet.this["k8s-cp-pri-a"]
  id = "SUBNET_ID"
}

import {
  to = module.network.aws_subnet.this["k8s-cp-pri-c"]
  id = "SUBNET_ID"
}

import {
  to = module.network.aws_subnet.this["k8s-dp-pri-a"]
  id = "SUBNET_ID"
}

import {
  to = module.network.aws_subnet.this["k8s-dp-pri-c"]
  id = "SUBNET_ID"
}

import {
  to = module.network.aws_subnet.this["common-pri-a"]
  id = "SUBNET_ID"
}

import {
  to = module.network.aws_subnet.this["common-pri-c"]
  id = "SUBNET_ID"
}

# NAT Gateways
import {
  to = module.network.aws_nat_gateway.this["ap-northeast-2a"]
  id = "NAT_GW_ID"
}

import {
  to = module.network.aws_nat_gateway.this["ap-northeast-2c"]
  id = "NAT_GW_ID"
}

# Route Tables
import {
  to = module.network.aws_route_table.public
  id = "RT_ID"
}

import {
  to = module.network.aws_route_table.private["ap-northeast-2a"]
  id = "RT_ID"
}

import {
  to = module.network.aws_route_table.private["ap-northeast-2c"]
  id = "RT_ID"
}

import {
  to = module.network.aws_route_table.db["ap-northeast-2a"]
  id = "RT_ID"
}

import {
  to = module.network.aws_route_table.db["ap-northeast-2c"]
  id = "RT_ID"
}
*/
