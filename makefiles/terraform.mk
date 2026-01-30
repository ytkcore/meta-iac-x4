# =============================================================================
# Terraform Makefile - Infrastructure Lifecycle Management
# =============================================================================

# -----------------------------------------------------------------------------
# Initialization
# -----------------------------------------------------------------------------
.PHONY: env-init tf-init init-upgrade

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
	@$(TF_STACK) plan $(TF_VAR_FILES) $(TF_OPTS)

apply: tf-init tunnel-check
	@$(TF_STACK) apply $(TF_VAR_FILES) $(TF_OPTS)

apply-auto: tf-init tunnel-check
	@$(TF_STACK) apply -auto-approve $(TF_VAR_FILES) $(TF_OPTS)

destroy: tf-init tunnel-check
	@bash scripts/terraform/pre-destroy-hook.sh "$(STACK)"
	@$(TF_STACK) destroy $(TF_VAR_FILES) $(TF_OPTS)

refresh: tf-init tunnel-check
	@$(TF_STACK) apply -refresh-only $(TF_VAR_FILES) $(TF_OPTS)


