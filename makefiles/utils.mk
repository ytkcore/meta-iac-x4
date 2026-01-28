# ==============================================================================
# 🐳 Harbor Operations (Level 3: Smart S3 + SSM + Governance)
# ==============================================================================

# -----------------------------------------------------------------------------
# 1. Configuration
# -----------------------------------------------------------------------------
HARBOR_STACK_NAME  := 45-harbor
HARBOR_VERSION     := 2.9.1

# [변경] 버킷 이름 규칙(글로벌 유니크): {환경}-harbor-storage-{accountId}-{region}
# 예) dev-harbor-storage-123456789012-ap-northeast-2
AWS_ACCOUNT_ID := $(or $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null),unknown)
HARBOR_BUCKET_NAME := $(ENV)-harbor-storage-$(AWS_ACCOUNT_ID)-$(STATE_REGION)

# [설정] 중앙 관리 파일 및 타겟 링크 경로 정의
# 공통 파일: modules/common_versions.tf
# 타겟 파일: stacks/{env}/{stack}/versions.tf
COMMON_VERSION_FILE := modules/common_versions.tf
TARGET_VERSION_FILE := stacks/$(ENV)/$(STACK)/versions.tf

# -----------------------------------------------------------------------------
# 2. Smart Bucket Logic
# -----------------------------------------------------------------------------
ifeq ($(STACK),$(HARBOR_STACK_NAME))
    BUCKET_CHECK := $(shell aws s3api head-bucket --bucket $(HARBOR_BUCKET_NAME) 2>&1 || echo "NOT_FOUND")
	TF_ARGS += -var='state_bucket=$(STATE_BUCKET)'

    ifneq (,$(findstring NOT_FOUND,$(BUCKET_CHECK)))
        TF_ARGS += -var='target_bucket_name=$(HARBOR_BUCKET_NAME)' -var='create_bucket=true'
    else ifneq (,$(findstring 404,$(BUCKET_CHECK)))
        TF_ARGS += -var='target_bucket_name=$(HARBOR_BUCKET_NAME)' -var='create_bucket=true'
    else
        TF_ARGS += -var='target_bucket_name=$(HARBOR_BUCKET_NAME)' -var='create_bucket=false'
    endif
endif

# -----------------------------------------------------------------------------
# 3. Governance: Versions Reference (Symlink Strategy)
# -----------------------------------------------------------------------------
.PHONY: versions-gen verify-version-file

verify-version-file:
	@if [ ! -f "$(COMMON_VERSION_FILE)" ]; then \
		echo "❌ Error: Central version file not found at $(COMMON_VERSION_FILE)"; \
		exit 1; \
	fi

versions-gen: verify-version-file
	@echo "🔗 [Governance] Linking Terraform versions for stack '$(STACK)'..."
	@mkdir -p stacks/$(ENV)/$(STACK)
	
	@# 심볼릭 링크 생성 (상대 경로: stacks/env/stack -> root -> modules)
	@# ../../../modules/common_versions.tf 를 가리키게 됨
	@ln -sf ../../../$(COMMON_VERSION_FILE) $(TARGET_VERSION_FILE)
	
	@echo "✅ Linked: $(TARGET_VERSION_FILE) -> ../../../$(COMMON_VERSION_FILE)"

# -----------------------------------------------------------------------------
# 4. Deployment Commands
# -----------------------------------------------------------------------------
.PHONY: deploy-app _deploy-harbor-ssm

deploy-app:
ifeq ($(STACK),$(HARBOR_STACK_NAME))
	@echo "🚀 [Deploy-App] Detected Harbor Stack. Starting..."
	@$(MAKE) _deploy-harbor-ssm
else
	@echo "ℹ️  [Deploy-App] Skipping: Not a Harbor stack."
endif

_deploy-harbor-ssm:
	@echo "🔍 Fetching Instance ID..."
	$(eval INSTANCE_ID := $(shell terraform -chdir="stacks/$(ENV)/$(HARBOR_STACK_NAME)" output -raw instance_id 2>/dev/null))
	@if [ -z "$(INSTANCE_ID)" ]; then echo "❌ Error: Instance ID not found."; exit 1; fi
	
	@echo "🚀 Deploying Harbor $(HARBOR_VERSION) to $(INSTANCE_ID)..."
	@aws ssm send-command \
		--document-name "AWS-RunShellScript" \
		--targets "Key=InstanceIds,Values=$(INSTANCE_ID)" \
		--parameters 'commands=["$(shell cat scripts/install-harbor.sh | sed 's/"/\\"/g' | sed "s/'/'\\\\''/g")", "$(ENV)", "harbor", "$(HARBOR_VERSION)"]' \
		--comment "Deploy Harbor $(HARBOR_VERSION)" \
		--output text \
		--query "Command.CommandId"
	@echo "✅ Command Sent!"

# -----------------------------------------------------------------------------
# 5. Clean Up
# -----------------------------------------------------------------------------
.PHONY: clean
#clean:
#	@echo "🧹 Cleaning up generated files for stack '$(STACK)'..."
#	@rm -f $(TARGET_VERSION_FILE)
#	@echo "   - Removed: $(TARGET_VERSION_FILE)"
#	@echo "✅ Clean complete."

# -----------------------------------------------------------------------------
# Clean
# -----------------------------------------------------------------------------
clean:
	@# .terraform, plan artifacts, local state 등 제거(원복 아님)
	rm -rf artifacts || true
	find stacks modules -name ".terraform" -type d -prune -exec rm -rf {} + || true
	find stacks modules -name ".terraform.lock.hcl" -type f -delete || true
	find stacks modules -name "domain.auto.tfvars" -type f -delete || true
	find stacks modules -name "env.auto.tfvars" -type f -delete || true
	find stacks -name "terraform.tfstate*" -type f -delete || true