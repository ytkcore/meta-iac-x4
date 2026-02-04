# =============================================================================
# Packer Makefile
# Golden Image Build Automation
# =============================================================================

PACKER_DIR := scripts/packer

.PHONY: packer-init packer-validate packer-build packer-cleanup

## Packer: Initialize Packer plugins
packer-init:
	@echo "==> Initializing Packer..."
	@cd $(PACKER_DIR) && packer init golden-image.pkr.hcl

## Packer: Validate template
packer-validate: packer-init
	@echo "==> Validating Packer template..."
	@cd $(PACKER_DIR) && packer validate golden-image.pkr.hcl

## Packer: Build Golden Image AMI
packer-build: packer-validate
	@echo "==> Building Golden Image..."
	@cd $(PACKER_DIR) && ./build.sh build

## Packer: Cleanup old AMIs (keep last 3)
packer-cleanup:
	@echo "==> Cleaning up old Golden Image AMIs..."
	@cd $(PACKER_DIR) && ./build.sh cleanup 3

## Packer: Full build with aws-vault
golden-image-build:
	@echo "==> Building Golden Image with aws-vault..."
	@aws-vault exec $(AWS_PROFILE) -- $(MAKE) packer-build
