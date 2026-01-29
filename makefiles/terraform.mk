# -----------------------------------------------------------------------------
# Terraform Lifecycle

TF_VAR_FILES := $(ENV_TFVARS) $(ENV_AUTO_TFVARS)
# -----------------------------------------------------------------------------
.PHONY: tf-init init-upgrade plan apply apply-auto destroy refresh plan-all apply-all env-init

env-init:
	@bash scripts/common/ensure-base-domain.sh "$(ENV)"

# [CHANGED] Renamed 'init' to 'tf-init' to avoid conflict with main Makefile 'init' (env setup)
tf-init: env-init versions-gen
	@$(TF_STACK) init -upgrade=false \
	  -backend-config="../../$(BACKEND_CONFIG_FILE)" \
	  -backend-config="key=$(STATE_KEY_PREFIX)/$(ENV)/$(STACK).tfstate" \
	  -reconfigure

init-upgrade: versions-gen
	@$(TF_STACK) init -upgrade \
	  -backend-config="../../$(BACKEND_CONFIG_FILE)" \
	  -backend-config="key=$(STATE_KEY_PREFIX)/$(ENV)/$(STACK).tfstate" \
	  -reconfigure

# Dependencies updated to use tf-init
plan: tf-init
	@$(TF_STACK) plan $(TF_VAR_FILES) $(TF_OPTS)

apply: tf-init
	@$(TF_STACK) apply $(TF_VAR_FILES) $(TF_OPTS)

apply-auto: tf-init
	@$(TF_STACK) apply -auto-approve $(TF_VAR_FILES) $(TF_OPTS)

# 55-rancher/55-bootstrap 스택의 경우 Helm/K8s 리소스 정리 후 destroy
destroy: tf-init _pre-destroy-hook
	@$(TF_STACK) destroy $(TF_VAR_FILES) $(TF_OPTS)

# Pre-destroy hook: 55-rancher or 55-bootstrap 스택일 때만 K8s 리소스 정리
_pre-destroy-hook:
ifneq (,$(filter $(STACK),55-rancher 55-bootstrap))
	@echo "==> [$(STACK)] Pre-destroy cleanup: Helm releases and namespaces..."
	@helm uninstall rancher -n cattle-system 2>/dev/null || true
	@helm uninstall cert-manager -n cert-manager 2>/dev/null || true
	@kubectl delete namespace cattle-system --ignore-not-found --timeout=60s 2>/dev/null || true
	@kubectl delete namespace cert-manager --ignore-not-found --timeout=60s 2>/dev/null || true
	@kubectl delete crd -l app.kubernetes.io/name=cert-manager 2>/dev/null || true
	@echo "==> [$(STACK)] Pre-destroy cleanup completed."
endif

refresh: tf-init
	@$(TF_STACK) apply -refresh-only $(TF_VAR_FILES) $(TF_OPTS)

# 전체 스택 일괄 실행
plan-all:
	@for s in $(STACK_ORDER); do \
	  echo "==> PLAN $(ENV)/$$s"; \
	  $(MAKE) plan ENV=$(ENV) STACK=$$s; \
	done

apply-all:
	@for s in $(STACK_ORDER); do \
	  echo "==> APPLY $(ENV)/$$s"; \
	  $(MAKE) apply ENV=$(ENV) STACK=$$s; \
	done

# -----------------------------------------------------------------------------
# Code Quality (Merged from qa.mk)
# -----------------------------------------------------------------------------
.PHONY: fmt check check-ci lint lint-all

fmt:
	terraform fmt -recursive

check: versions-gen
	@terraform fmt -check -recursive; rc=$$?; \
	if [ $$rc -eq 3 ]; then \
	  echo "INFO: terraform fmt가 필요합니다. (rc=3)"; \
	  terraform fmt -check -recursive 2>/dev/null || true; \
	  exit 0; \
	elif [ $$rc -eq 0 ]; then \
	  echo "OK: terraform fmt"; \
	  exit 0; \
	else \
	  echo "ERROR: terraform fmt 실패(rc=$$rc)"; \
	  exit $$rc; \
	fi

check-ci: versions-gen
	terraform fmt -check -recursive

lint: versions-gen
	@command -v tflint >/dev/null 2>&1 || (echo "tflint not found."; exit 2)
	tflint --init
	tflint

lint-all: versions-gen
	@command -v tflint >/dev/null 2>&1 || (echo "tflint not found."; exit 2)
	tflint --init
	@set -e; \
	for d in $$(find modules stacks -mindepth 2 -maxdepth 2 -type d); do \
	  if ls $$d/*.tf >/dev/null 2>&1; then \
	    echo "==> tflint $$d"; \
	    (cd $$d && tflint); \
	  fi; \
	done
# Destroy all stacks in reverse order, then backend bucket
.PHONY: destroy-all
destroy-all:
	@echo "⚠️  WARNING: Complete Infrastructure Teardown"
	@echo "This will destroy ALL stacks in reverse order and the S3 backend bucket!"
	@echo ""
	@read -p "Are you sure you want to proceed? (yes/no): " CONFIRM; \
	if [ "$$CONFIRM" != "yes" ]; then \
	  echo "Aborted."; \
	  exit 1; \
	fi
	@echo "Starting complete teardown..."
	@echo ""
	@for s in $$(echo "$(STACK_ORDER)" | tr ' ' '\n' | tail -r | tr '\n' ' '); do \
	  echo "===> DESTROY $(ENV)/$$s"; \
	  STATE_KEY="$(STATE_KEY_PREFIX)/$(ENV)/$$s.tfstate"; \
	  if [ -f "$(BACKEND_CONFIG_FILE)" ]; then \
	    STATE_BUCKET="$$(grep -E '^bucket' $(BACKEND_CONFIG_FILE) | sed -E 's/.*\"([^\"]+)\".*/\1/')" && \
	    aws s3api head-object --bucket "$$STATE_BUCKET" --key "$$STATE_KEY" >/dev/null 2>&1; \
	    if [ $$? -eq 0 ]; then \
	      if $(MAKE) destroy ENV=$(ENV) STACK=$$s -auto-approve 2>&1; then \
	        echo "✓ Destroyed $$s"; \
	      else \
	        echo "✗ Failed to destroy $$s, but continuing..."; \
	      fi; \
	    else \
	      echo "⊘ Stack $$s does not exist (no state found), skipping..."; \
	    fi; \
	  else \
	    if $(MAKE) destroy ENV=$(ENV) STACK=$$s -auto-approve 2>&1; then \
	      echo "✓ Destroyed $$s"; \
	    else \
	      echo "⊘ Stack $$s may not exist, skipping..."; \
	    fi; \
	  fi; \
	  echo ""; \
	done
	@echo "===> Final Step: Destroying S3 Backend Bucket"
	@if [ -f "$(BACKEND_CONFIG_FILE)" ]; then \
	  STATE_BUCKET="$$(grep -E '^bucket' $(BACKEND_CONFIG_FILE) | sed -E 's/.*\"([^\"]+)\".*/\1/')" && \
	  STATE_REGION="$$(grep -E '^region' $(BACKEND_CONFIG_FILE) | sed -E 's/.*\"([^\"]+)\".*/\1/')" && \
	  echo "Bucket: $$STATE_BUCKET ($$STATE_REGION)" && \
	  echo "Emptying bucket contents..." && \
	  aws s3 rm s3://$$STATE_BUCKET --recursive --region $$STATE_REGION 2>/dev/null || true && \
	  echo "Destroying backend bucket infrastructure..." && \
	  (cd $(BOOT_DIR) && \
	   terraform init -upgrade=false -reconfigure >/dev/null 2>&1 && \
	   terraform destroy -auto-approve \
	     -var="state_bucket=$$STATE_BUCKET" \
	     -var="state_region=$$STATE_REGION") && \
	  if aws s3api head-bucket --bucket "$$STATE_BUCKET" --region $$STATE_REGION 2>/dev/null; then \
	    echo "⚠ Bucket still exists after Terraform destroy, forcing deletion..." && \
	    aws s3 rb s3://$$STATE_BUCKET --region $$STATE_REGION --force && \
	    echo "✓ Backend bucket force-deleted: s3://$$STATE_BUCKET"; \
	  else \
	    echo "✓ Backend bucket destroyed: s3://$$STATE_BUCKET"; \
	  fi; \
	else \
	  echo "⚠ Backend config not found, skipping bucket cleanup."; \
	fi
	@echo ""
	@echo "✓ Complete teardown finished!"
	@echo "Environment $(ENV) has been completely removed."
