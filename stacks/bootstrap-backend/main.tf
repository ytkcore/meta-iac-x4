# -----------------------------------------------------------------------------
# Bootstrap Backend 스택
# - Terraform remote state를 위한 S3 버킷을 생성/설정합니다.
# - 이미 버킷이 존재하는 경우(OwnedByYou)에도 안전하게 적용될 수 있도록,
#   Makefile의 backend-bootstrap 단계에서 자동 import 후 apply 합니다.
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket
  # Allow clean teardown for reset/POC. WARNING: deletes ALL objects/versions in this bucket.
  force_destroy = true
  tags          = merge(var.tags, { Name = var.state_bucket })
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "tls_only" {
  bucket = aws_s3_bucket.tfstate.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.tfstate.arn,
          "${aws_s3_bucket.tfstate.arn}/*"
        ]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
  })
}
