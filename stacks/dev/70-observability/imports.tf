# =============================================================================
# Native Terraform Import Blocks - 70-observability
# =============================================================================

/*
# Longhorn Backup S3
import {
  to = aws_s3_bucket.longhorn_backup[0]
  id = "BUCKET_NAME"
}

# IAM Policy
import {
  to = aws_iam_policy.longhorn_backup[0]
  id = "POLICY_ARN"
}

# IAM Role Policy Attachment
import {
  to = aws_iam_role_policy_attachment.longhorn_backup[0]
  id = "ROLE_NAME/POLICY_ARN"
}
*/
