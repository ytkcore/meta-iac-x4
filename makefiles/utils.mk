# =============================================================================
# Utility Makefile - Maintenance & Quality Control
# =============================================================================

# -----------------------------------------------------------------------------
# Configuration Generation
# -----------------------------------------------------------------------------
.PHONY: versions-gen

versions-gen:
	@if [ ! -f "modules/common_versions.tf" ]; then \
		echo "❌ Error: modules/common_versions.tf not found"; exit 1; \
	fi
	@if [ ! -d "stacks/$(ENV)/$(STACK)" ]; then \
		echo "❌ Error: Stack directory 'stacks/$(ENV)/$(STACK)' does not exist."; exit 1; \
	fi
	@if [ ! -f "stacks/$(ENV)/$(STACK)/main.tf" ]; then \
		echo "❌ Error: 'main.tf' not found in stacks/$(ENV)/$(STACK). Is this a valid stack?"; exit 1; \
	fi
	@ln -sf ../../../modules/common_versions.tf stacks/$(ENV)/$(STACK)/versions.tf
	@echo "✅ Validated stack: $(STACK) ($(ENV))"
	@echo "✅ Linked versions.tf"

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

# -----------------------------------------------------------------------------
# Bulk Operations
# -----------------------------------------------------------------------------
.PHONY: plan-all apply-all apply-all-auto destroy-all import-all

import-all:
	@bash scripts/terraform/recover-all.sh "$(ENV)" "$(STACK)"

plan-all:
	@for s in $(STACK_ORDER); do echo "==> PLAN $(ENV)/$$s"; $(MAKE) plan ENV=$(ENV) STACK=$$s; done

apply-all:
	@for s in $(STACK_ORDER); do echo "==> APPLY $(ENV)/$$s"; $(MAKE) apply ENV=$(ENV) STACK=$$s; done

apply-all-auto:
	@for s in $(STACK_ORDER); do echo "==> APPLY-AUTO $(ENV)/$$s"; $(MAKE) apply-auto ENV=$(ENV) STACK=$$s || exit 1; done

destroy-all:
	@bash scripts/terraform/destroy-all.sh "$(ENV)" "$(STACK_ORDER)" "$(BACKEND_CONFIG_FILE)" "$(STATE_KEY_PREFIX)" "$(BOOT_DIR)"
