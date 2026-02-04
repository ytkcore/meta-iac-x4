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

# -----------------------------------------------------------------------------
# Core Operations
# -----------------------------------------------------------------------------
.PHONY: plan apply apply-auto destroy refresh

plan: tf-init tunnel-check
	@bash scripts/common/log-op.sh "PLAN" "$(STACK)" "$(ENV)"
	@$(TF_STACK) plan $(TF_VAR_FILES) $(TF_OPTS)

apply: tf-init tunnel-check
	@bash scripts/common/log-op.sh "APPLY" "$(STACK)" "$(ENV)"
	@if [ "$(STACK)" = "10-golden-image" ]; then \
		echo "==> Checking Golden Image..."; \
		bash scripts/golden-image/build-if-needed.sh; \
	fi
	@$(TF_STACK) apply $(TF_VAR_FILES) $(TF_OPTS)
	@if [ "$(STACK)" = "00-network" ]; then \
		$(MAKE) build-ami; \
	fi
	@bash scripts/terraform/post-apply-hook.sh "$(STACK)"

apply-auto: tf-init tunnel-check
	@bash scripts/common/log-op.sh "APPLY-AUTO" "$(STACK)" "$(ENV)"
	@if [ "$(STACK)" = "10-golden-image" ]; then \
		echo "==> Checking Golden Image..."; \
		bash scripts/golden-image/build-if-needed.sh; \
	fi
	@$(TF_STACK) apply -auto-approve $(TF_VAR_FILES) $(TF_OPTS)
	@if [ "$(STACK)" = "00-network" ]; then \
		$(MAKE) build-ami; \
	fi
	@bash scripts/terraform/post-apply-hook.sh "$(STACK)"

destroy: tf-init tunnel-check
	@bash scripts/common/log-op.sh "DESTROY" "$(STACK)" "$(ENV)"
	@bash scripts/terraform/pre-destroy-hook.sh "$(STACK)"
	@$(TF_STACK) destroy $(TF_VAR_FILES) $(TF_OPTS)
	@if [ "$(STACK)" = "10-golden-image" ]; then \
		echo "==> Cleaning up Golden Image AMIs..."; \
		bash scripts/golden-image/cleanup-amis.sh "$(STACK)"; \
	fi

refresh: tf-init tunnel-check
	@bash scripts/common/log-op.sh "REFRESH" "$(STACK)" "$(ENV)"
	@$(TF_STACK) apply -refresh-only $(TF_VAR_FILES) $(TF_OPTS)

# -----------------------------------------------------------------------------
# Import / Adoption (Native 1.5+ Transition)
# -----------------------------------------------------------------------------
import: tf-init
	@bash scripts/terraform/generate-imports.sh $(STACK) $(ENV)
	@$(TF_STACK) plan $(TF_VAR_FILES) $(TF_OPTS)
	@echo ""
	@echo "⚠️  [IMPORTANT] Native imports detected in plan."
	@echo "   If the plan looks correct (Adopting X resources), please run:"
	@echo "   make apply STACK=$(STACK) ENV=$(ENV)"
	@echo ""
