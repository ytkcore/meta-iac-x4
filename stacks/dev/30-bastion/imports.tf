# =============================================================================
# Native Terraform Import Blocks - 30-bastion
# =============================================================================


# Bastion Security Group (if not injected)
import {
  to = aws_security_group.bastion[0]
  id = "sg-055a6a34592dca501"
}

# Bastion Instance (via ec2-instance module)
import {
  to = module.bastion.aws_instance.this
  id = "i-03f11a30da19140b2"
}

