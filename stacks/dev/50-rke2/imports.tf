# =============================================================================
# Native Terraform Import Blocks - 50-rke2
# =============================================================================

/*
# IAM Policy
import {
  to = aws_iam_policy.external_dns[0]
  id = "POLICY_ARN"
}

# IAM Role Policy Attachment
import {
  to = aws_iam_role_policy_attachment.external_dns[0]
  id = "ROLE_NAME/POLICY_ARN"
}

# IAM Role & Instance Profile (via rke2 module)
import {
  to = module.rke2.aws_iam_role.nodes
  id = "ROLE_NAME"
}

import {
  to = module.rke2.aws_iam_instance_profile.nodes
  id = "PROFILE_NAME"
}

# Security Group
import {
  to = module.rke2.aws_security_group.nodes
  id = "SG_ID"
}

# Control Plane Instances
import {
  to = module.rke2.aws_instance.control_plane["cp-01"]
  id = "INSTANCE_ID"
}

import {
  to = module.rke2.aws_instance.control_plane["cp-02"]
  id = "INSTANCE_ID"
}

import {
  to = module.rke2.aws_instance.control_plane["cp-03"]
  id = "INSTANCE_ID"
}

# Worker Instances
import {
  to = module.rke2.aws_instance.worker["worker-01"]
  id = "INSTANCE_ID"
}

import {
  to = module.rke2.aws_instance.worker["worker-02"]
  id = "INSTANCE_ID"
}

import {
  to = module.rke2.aws_instance.worker["worker-03"]
  id = "INSTANCE_ID"
}

import {
  to = module.rke2.aws_instance.worker["worker-04"]
  id = "INSTANCE_ID"
}

# Internal NLB
import {
  to = module.rke2.aws_lb.rke2[0]
  id = "ALB_ARN"
}

# NLB Target Groups
import {
  to = module.rke2.aws_lb_target_group.supervisor[0]
  id = "TG_ARN"
}

import {
  to = module.rke2.aws_lb_target_group.apiserver[0]
  id = "TG_ARN"
}
*/
