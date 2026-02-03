# Harbor Stack Implementation Details

This document outlines the architectural decisions and configuration details for the Harbor registry stack (`40-harbor`).

## Architecture

### Components
- **EC2 Instance**: `t3.large`. Runs Harbor via Docker Compose (bootstrapped by User Data).
- **ALB (Application Load Balancer)**: Exposes Harbor to the public internet (HTTP/HTTPS).
- **S3 Bucket**: Stores Docker images and Helm charts (persistent storage).
- **Route53**: Manages `harbor.unifiedmeta.net` DNS record pointing to ALB.

### Network Placement
- **EC2**: Private Subnet (`common-pri-c` by default). Controlled via `harbor_subnet_key`.
- **ALB**: Public Subnets (`pub-*`). Auto-discovered via tag filter `*pub*`.

## Configuration Strategy

### Variable Management
All critical configuration values are centralized in `stacks/dev/env.tfvars` to properly inject into Terraform:
```hcl
# Remote State Configuration
state_bucket     = "dev-meta-tfstate"
state_region     = "ap-northeast-2"
state_key_prefix = "iac"

# Harbor Storage
target_bucket_name = "dev-harbor-storage-..."
```

### User Data & Bootstrapping
- **Compression**: User Data is Gzip-compressed (`base64gzip`) to bypass the AWS 16KB limit.
- **Module Interface**: `modules/ec2-instance` accepts `user_data_base64` to support compressed input.
- **Bootstrap Script**: `user_data.sh.tftpl` handles:
  1. Docker & Docker Compose installation.
  2. Formatting/Mounting data volume (`/data`).
  3. Harbor installation (offline bundle or online installer).
  4. Helm Chart Seeding (optional).

## Recent Changes (2026-01-30)
- **Subnet Filter Update**: Changed from `*public*` -> `*pub*` to match new naming convention.
- **Config Refactoring**: Removed `grep` logic from Makefile in favor of `env.tfvars`.
