# -----------------------------------------------------------------------------
# Essential Configuration
# -----------------------------------------------------------------------------
base_domain = "unifiedmeta.net"
project     = "meta"
env         = "dev"

# -----------------------------------------------------------------------------
# Remote State Configuration (for cross-stack references)
# -----------------------------------------------------------------------------
state_bucket     = "dev-meta-tfstate"
state_region     = "ap-northeast-2"
state_key_prefix = "iac"

# -----------------------------------------------------------------------------
# Harbor Configuration
# -----------------------------------------------------------------------------
target_bucket_name = "dev-harbor-storage-599913747911-ap-northeast-2"

# -----------------------------------------------------------------------------
# Optional Overrides (Uncomment to change defaults)
# -----------------------------------------------------------------------------
# region = "ap-northeast-2"
# azs    = ["ap-northeast-2a", "ap-northeast-2c"]

# db_instance_type   = "t3.large"
# postgres_image_tag = "18.1"
# 50-rke2
enable_public_ingress_nlb           = true
enable_public_ingress_http_listener = true

# 55-bootstrap
kubeconfig_path = "~/.kube/config-rke2-dev"
