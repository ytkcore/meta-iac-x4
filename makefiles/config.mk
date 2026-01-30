# =============================================================================
# Configuration & Variables
# =============================================================================

ENV   ?= dev
STACK ?= 00-network

STACK_DIR := stacks/$(ENV)/$(STACK)
BOOT_DIR  := stacks/bootstrap-backend

export TF_PLUGIN_CACHE_DIR ?= $(HOME)/.terraform.d/plugin-cache
_ := $(shell mkdir -p $(TF_PLUGIN_CACHE_DIR))

TF_OPTS ?= -compact-warnings
TF_STACK := terraform -chdir=$(STACK_DIR)
TF_VAR_FILES := -var-file=../env.tfvars $(if $(wildcard stacks/$(ENV)/env.auto.tfvars),-var-file=../env.auto.tfvars,)

BACKEND_CONFIG_FILE := stacks/$(ENV)/backend.hcl
STATE_KEY_PREFIX := iac
BACKEND_OPTS := -backend-config="../../../$(BACKEND_CONFIG_FILE)" \
                -backend-config="key=$(STATE_KEY_PREFIX)/$(ENV)/$(STACK).tfstate"

STACK_ORDER := 00-network 10-security 20-endpoints 30-db 40-bastion 50-rke2 55-bootstrap 60-db

# -----------------------------------------------------------------------------
# Harbor Stack Configuration
# -----------------------------------------------------------------------------
HARBOR_STACK_NAME  := 45-harbor
# Read bucket name from env.tfvars
HARBOR_BUCKET_NAME := $(shell grep 'target_bucket_name' stacks/$(ENV)/env.tfvars 2>/dev/null | cut -d'"' -f2)

ifeq ($(STACK),$(HARBOR_STACK_NAME))
    # Check if bucket exists: Success(0) -> Exists -> create=false | Failure -> Missing -> create=true
    # Note: Requires HARBOR_BUCKET_NAME to be set in env.tfvars
    SHOULD_CREATE_BUCKET := $(shell aws s3api head-bucket --bucket $(HARBOR_BUCKET_NAME) 2>/dev/null && echo "false" || echo "true")
    
    TF_OPTS += -var='create_bucket=$(SHOULD_CREATE_BUCKET)'
endif
