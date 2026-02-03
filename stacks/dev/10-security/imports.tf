# =============================================================================
# Native Terraform Import Blocks - 10-security
# =============================================================================

/*
# Security Groups
import {
  to = module.security_groups.aws_security_group.bastion
  id = "SG_ID"
}

import {
  to = module.security_groups.aws_security_group.breakglass_ssh
  id = "SG_ID"
}

import {
  to = module.security_groups.aws_security_group.lb_public
  id = "SG_ID"
}

import {
  to = module.security_groups.aws_security_group.k8s_cp
  id = "SG_ID"
}

import {
  to = module.security_groups.aws_security_group.k8s_worker
  id = "SG_ID"
}

import {
  to = module.security_groups.aws_security_group.db
  id = "SG_ID"
}

import {
  to = module.security_groups.aws_security_group.vpce
  id = "SG_ID"
}

import {
  to = module.security_groups.aws_security_group.k8s_client
  id = "SG_ID"
}

import {
  to = module.security_groups.aws_security_group.ops_client
  id = "SG_ID"
}

import {
  to = module.security_groups.aws_security_group.monitoring_client
  id = "SG_ID"
}

# Rules
import {
  to = module.security_groups.aws_security_group_rule.k8s_cp_etcd_self
  id = "SG_RULE_ID" # Format: sg-xxx_ingress_tcp_2379_2380_sg-xxx
}
*/
