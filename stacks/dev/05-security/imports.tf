# =============================================================================
# Native Terraform Import Blocks - 10-security
# =============================================================================


# Security Groups
import {
  to = module.security_groups.aws_security_group.bastion
  id = "sg-0c3b02abef4193432"
}

import {
  to = module.security_groups.aws_security_group.breakglass_ssh
  id = "sg-0f5aba693075ea835"
}

import {
  to = module.security_groups.aws_security_group.lb_public
  id = "sg-045bc0b51cd51b647"
}

import {
  to = module.security_groups.aws_security_group.k8s_cp
  id = "sg-0a16da68a01593519"
}

import {
  to = module.security_groups.aws_security_group.k8s_worker
  id = "sg-09c48388831f50c7d"
}

import {
  to = module.security_groups.aws_security_group.db
  id = "sg-0d11a235c7a132af1"
}

import {
  to = module.security_groups.aws_security_group.vpce
  id = "sg-02edb178abc0069f7"
}

import {
  to = module.security_groups.aws_security_group.k8s_client
  id = "sg-058669c77dc1e85ea"
}

import {
  to = module.security_groups.aws_security_group.ops_client
  id = "sg-0ab1ae6b024d5bdcc"
}

import {
  to = module.security_groups.aws_security_group.monitoring_client
  id = "sg-0f0f37a8531ed86fd"
}

# Rules




