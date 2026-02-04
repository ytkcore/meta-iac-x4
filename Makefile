SHELL := /usr/bin/env bash

# =============================================================================
# Terraform IaC - Main Entry Point
# =============================================================================

include makefiles/config.mk
include makefiles/ssm.mk
include makefiles/terraform.mk
include makefiles/utils.mk
include makefiles/packer.mk

.PHONY: help whoami init

init:
	@scripts/common/init-env.sh

check-ami:
	@scripts/common/check-ami.sh

build-ami:
	@chmod +x scripts/common/build-ami.sh
	@scripts/common/build-ami.sh

status:
	@scripts/common/check-status.sh $(ENV) $(STACK)

help:
	@echo 'Usage:'
	@echo ''
	@echo '  (1) Initial Setup:'
	@echo '      aws-vault exec <profile> -- make init ENV=dev'
	@echo ''
	@echo '  (2) Terraform Operations:'
	@echo '      make plan  ENV=dev STACK=00-network'
	@echo '      make apply ENV=dev STACK=00-network'
	@echo '      make status ENV=dev STACK=00-network # Check resource status'
	@echo ''
	@echo '  (3) Code Quality:'
	@echo '      make check       # Format check'
	@echo '      make lint-all    # Static analysis'
	@echo '      make clean       # Clean artifacts'

whoami:
	@aws sts get-caller-identity