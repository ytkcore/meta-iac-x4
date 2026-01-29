# =============================================================================
# Terraform Makefile - Infrastructure Lifecycle Management
# =============================================================================

# -----------------------------------------------------------------------------
# Initialization
# -----------------------------------------------------------------------------
.PHONY: env-init tf-init init-upgrade versions-gen

env-init:
	@bash scripts/common/ensure-base-domain.sh "$(ENV)"

tf-init: env-init versions-gen
	@$(TF_STACK) init -upgrade=false $(BACKEND_OPTS) -reconfigure

init-upgrade: versions-gen
	@$(TF_STACK) init -upgrade $(BACKEND_OPTS) -reconfigure

versions-gen:
	@if [ ! -f "modules/common_versions.tf" ]; then \
		echo "❌ Error: modules/common_versions.tf not found"; exit 1; \
	fi
	@mkdir -p stacks/$(ENV)/$(STACK)
	@ln -sf ../../../modules/common_versions.tf stacks/$(ENV)/$(STACK)/versions.tf
	@echo "✅ Linked versions.tf"

# -----------------------------------------------------------------------------
# Core Operations
# -----------------------------------------------------------------------------
.PHONY: plan apply apply-auto destroy refresh

plan: tf-init
	@$(TF_STACK) plan $(TF_VAR_FILES) $(TF_OPTS)

apply: tf-init
	@$(TF_STACK) apply $(TF_VAR_FILES) $(TF_OPTS)

apply-auto: tf-init
	@$(TF_STACK) apply -auto-approve $(TF_VAR_FILES) $(TF_OPTS)

destroy: tf-init
	@bash scripts/terraform/pre-destroy-hook.sh "$(STACK)"
	@$(TF_STACK) destroy $(TF_VAR_FILES) $(TF_OPTS)

refresh: tf-init
	@$(TF_STACK) apply -refresh-only $(TF_VAR_FILES) $(TF_OPTS)

# -----------------------------------------------------------------------------
# Bulk Operations
# -----------------------------------------------------------------------------
.PHONY: plan-all apply-all destroy-all

plan-all:
	@for s in $(STACK_ORDER); do echo "==> PLAN $(ENV)/$$s"; $(MAKE) plan ENV=$(ENV) STACK=$$s; done

apply-all:
	@for s in $(STACK_ORDER); do echo "==> APPLY $(ENV)/$$s"; $(MAKE) apply ENV=$(ENV) STACK=$$s; done

destroy-all:
	@bash scripts/terraform/destroy-all.sh "$(ENV)" "$(STACK_ORDER)" "$(BACKEND_CONFIG_FILE)" "$(STATE_KEY_PREFIX)" "$(BOOT_DIR)"

# -----------------------------------------------------------------------------
# Code Quality
# -----------------------------------------------------------------------------
.PHONY: fmt check lint lint-all

fmt:
	terraform fmt -recursive

check:
	terraform fmt -check -recursive

lint:
	tflint --init && tflint

lint-all:
	@bash scripts/terraform/lint-all.sh

# -----------------------------------------------------------------------------
# Clean Up
# -----------------------------------------------------------------------------
.PHONY: clean clean-cache

clean:
	rm -rf artifacts || true
	find stacks modules -name ".terraform" -type d -prune -exec rm -rf {} + || true
	find stacks modules -name ".terraform.lock.hcl" -type f -delete || true
	find stacks modules -name "*.auto.tfvars" -type f -delete || true
	find stacks -name "terraform.tfstate*" -type f -delete || true
	@echo "🧹 Cleaned. Run 'make clean-cache' to remove plugin cache."

clean-cache:
	@if [ -d "$(TF_PLUGIN_CACHE_DIR)" ]; then \
		rm -rf "$(TF_PLUGIN_CACHE_DIR)"; echo "✅ Cache cleaned."; \
	else \
		echo "ℹ️  Cache not found."; \
	fi
