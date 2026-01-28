################################################################################
# Terraform Backend Configuration
# 
# Note: bucket, region, key 값은 terraform init 시 -backend-config로 주입하거나
# Makefile/CI에서 관리합니다.
################################################################################

terraform {
  backend "s3" {
    encrypt = true
  }
}
