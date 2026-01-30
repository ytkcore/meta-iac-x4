# Harbor Deployment Troubleshooting (2026-01-30)

This log documents the resolution of deployment issues encountered during the Harbor stack setup following a major network refactoring.

## Issue 1: ALB Subnet Discovery Failure
- **Symptom:** `ValidationError: At least two subnets ... must be specified`
- **Root Cause:** The `aws_subnets` filter was looking for `tag:Name = *public*`. The subnet naming convention had changed to use `-pub-` (e.g., `dev-meta-snet-pub-a`).
- **Resolution:** Updated the filter in `stacks/dev/45-harbor/main.tf`:
  ```hcl
  filter {
    name   = "tag:Name"
    values = ["*pub*"]
  }
  ```

## Issue 2: Missing Remote State Variables
- **Symptom:** `Error: var.state_key_prefix is null`
- **Root Cause:** The Makefile relied on fragile `grep` commands to extract backend config from `backend.hcl` and inject them as `TF_VAR_` environment variables. This pipeline broke during refactoring or was insufficient.
- **Resolution:**
  - Migrated configuration to `stacks/dev/env.tfvars`.
  - Added `state_bucket`, `state_region`, `state_key_prefix` to `env.tfvars`.
  - Updated `config.mk` to remove the grep logic.

## Issue 3: User Data Size Limit Exceeded
- **Symptom:** `InvalidParameterValue: User data is limited to 16384 bytes`
- **Root Cause:** The combined size of Harbor bootstrap scripts (embedded via `templatefile`) exceeded the 16KB AWS limit.
- **Resolution:**
  - Implemented Gzip compression for User Data.
  - Modified `modules/ec2-instance` to accept a new input variable `user_data_base64`.
  - Updated `modules/harbor-ec2` to pass `base64gzip(templatefile(...))`.

## Verification
The deployment was successfully verified with:
- `make apply STACK=45-harbor`
- Health check of Harbor endpoint: `https://harbor.unifiedmeta.net`
