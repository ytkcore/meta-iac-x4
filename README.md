# Cloud Infrastructure Project

DevSecOps-oriented infrastructure automation with Terraform and Makefile.

## Quick Start (Dev)

```bash
# 1. Initialize environment
make env-init ENV=dev

# 2. Deploy Network
aws-vault exec devops -- make apply STACK=00-network

# 3. Deploy Harbor
aws-vault exec devops -- make apply STACK=40-harbor
```

## Documentation

### 📘 Operations
- **[Day-2 Runbook](./docs/runbooks/day-2-operations.md)**: Standard operating procedures and commands.

### 🏗 Architecture
- **[Naming Convention](./docs/architecture/naming-convention.md)**: Resource naming standards (`pub/pri`, `common`, etc).

### 🛠 Implementation Details
- **[Harbor Stack](./docs/implementation/harbor-stack.md)**: Architecture and configuration of the private registry.

### 🔧 Troubleshooting Logs
- **[Harbor Deployment Fixes (2026-01-30)](./docs/troubleshooting/harbor-deployment-fix.md)**: Log of fixes for subnet filters, user data size, and config management.
