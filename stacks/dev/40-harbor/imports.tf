# =============================================================================
# Native Terraform Import Blocks - 40-harbor
# =============================================================================

/*
# EC2 Instance (via harbor-ec2 module)
import {
  to = module.harbor.module.ec2.aws_instance.this
  id = "INSTANCE_ID"
}

# ALB
import {
  to = module.harbor.aws_lb.harbor[0]
  id = "ALB_ARN"
}

# S3 Bucket
import {
  to = module.harbor.aws_s3_bucket.created[0]
  id = "BUCKET_NAME"
}

# Route53 Records (Split-Horizon)
import {
  to = aws_route53_record.harbor_public[0]
  id = "ZONE_ID_harbor.base_domain_CNAME"
}

import {
  to = aws_route53_record.harbor_private[0]
  id = "ZONE_ID_harbor.base_domain_CNAME"
}
*/
