SHELL := /usr/bin/env bash

# =============================================================================
# Terraform IaC - Main Entry Point
# =============================================================================

include makefiles/config.mk
include makefiles/ssm.mk
include makefiles/terraform.mk
include makefiles/utils.mk

.PHONY: help whoami init

init:
	@scripts/common/init-env.sh

help:
	@echo 'Usage:'
	@echo ''
	@echo '  (1) Initial Setup:'
	@echo '      aws-vault exec <profile> -- make init ENV=dev'
	@echo ''
	@echo '  (2) Terraform Operations:'
	@echo '      make plan  ENV=dev STACK=00-network'
	@echo '      make apply ENV=dev STACK=00-network'
	@echo ''
	@echo '  (3) Code Quality:'
	@echo '      make check       # Format check'
	@echo '      make lint-all    # Static analysis'
	@echo '      make clean       # Clean artifacts'

whoami:
	@aws sts get-caller-identity