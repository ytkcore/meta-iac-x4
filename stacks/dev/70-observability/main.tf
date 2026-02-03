provider "aws" {
  region = var.region
}

locals {
  common_tags = {
    ManagedBy   = "terraform"
    Project     = var.project
    Environment = var.env
  }
}

# ------------------------------------------------------------------------------
# Remote State: RKE2 Cluster Info (to get Node IAM Role)
# ------------------------------------------------------------------------------
data "terraform_remote_state" "rke2" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.state_region
    key    = "${var.state_key_prefix}/${var.env}/50-rke2.tfstate"
  }
}

# ------------------------------------------------------------------------------
# Longhorn S3 Backup Bucket & IAM Policy
# ------------------------------------------------------------------------------
resource "aws_s3_bucket" "longhorn_backup" {
  count  = var.longhorn_backup_bucket != "" ? 1 : 0
  bucket = var.longhorn_backup_bucket
  tags   = local.common_tags
}

resource "aws_iam_policy" "longhorn_backup" {
  count       = var.longhorn_backup_bucket != "" ? 1 : 0
  name        = "${var.env}-${var.project}-longhorn-backup-policy"
  description = "Permissions for Longhorn to backup to S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.longhorn_backup_bucket}",
          "arn:aws:s3:::${var.longhorn_backup_bucket}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "longhorn_backup" {
  count      = var.longhorn_backup_bucket != "" ? 1 : 0
  role       = try(data.terraform_remote_state.rke2.outputs.iam_role_name, "")
  policy_arn = aws_iam_policy.longhorn_backup[0].arn
}
