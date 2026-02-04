# =============================================================================
# Configuration & Variables
# =============================================================================

ENV   ?= dev
STACK ?= 00-network

# Auto-detect Kubeconfig for RKE2
# If the environment-specific kubeconfig exists, use it.
KUBECONFIG_RKE2 := $(HOME)/.kube/config-rke2-$(ENV)
ifneq ("$(wildcard $(KUBECONFIG_RKE2))","")
    export KUBECONFIG := $(KUBECONFIG_RKE2)
endif

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

STACK_ORDER := $(strip 00-network 10-security 15-teleport 20-waf 30-bastion 40-harbor 50-rke2 55-bootstrap 60-db 70-observability)

# -----------------------------------------------------------------------------
# Harbor Stack Configuration
# -----------------------------------------------------------------------------
HARBOR_STACK_NAME  := 40-harbor
# Read bucket name from env.tfvars (handle potential missing value)
HARBOR_BUCKET_NAME := $(shell grep 'target_bucket_name' stacks/$(ENV)/env.tfvars 2>/dev/null | cut -d'"' -f2 | tr -d ' ')

ifeq ($(STACK),$(HARBOR_STACK_NAME))
    ifneq ($(HARBOR_BUCKET_NAME),)
        # Check if bucket exists: Success(0) -> Exists -> create=false | Failure -> Missing -> create=true
        SHOULD_CREATE_BUCKET := $(shell aws s3api head-bucket --bucket $(HARBOR_BUCKET_NAME) 2>/dev/null && echo "false" || echo "true")
        TF_OPTS += -var='create_bucket=$(SHOULD_CREATE_BUCKET)'
    endif
endif
