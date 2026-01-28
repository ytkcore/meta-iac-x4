# -----------------------------------------------------------------------------
# Terraform Lifecycle

TF_VAR_FILES := $(ENV_TFVARS) $(ENV_AUTO_TFVARS)
# -----------------------------------------------------------------------------
.PHONY: init init-upgrade plan apply apply-auto destroy refresh plan-all apply-all env-init

env-init:
	@bash scripts/ensure-base-domain.sh "$(ENV)"

init: env-init versions-gen
	@$(TF_STACK) init -upgrade=false \
	  -backend-config="bucket=$(STATE_BUCKET)" \
	  -backend-config="key=$(STATE_KEY_PREFIX)/$(ENV)/$(STACK).tfstate" \
	  -backend-config="region=$(STATE_REGION)" \
	  -backend-config="use_lockfile=true" \
	  -reconfigure

init-upgrade: versions-gen
	@$(TF_STACK) init -upgrade \
	  -backend-config="bucket=$(STATE_BUCKET)" \
	  -backend-config="key=$(STATE_KEY_PREFIX)/$(ENV)/$(STACK).tfstate" \
	  -backend-config="region=$(STATE_REGION)" \
	  -backend-config="use_lockfile=true" \
	  -reconfigure

plan: init
	@$(TF_STACK) plan $(TF_VAR_FILES) $(TF_ARGS)

apply: init
	@$(TF_STACK) apply $(TF_VAR_FILES) $(TF_ARGS)

apply-auto: init
	@$(TF_STACK) apply -auto-approve $(TF_VAR_FILES) $(TF_ARGS)

# 55-rancher 스택의 경우 Helm/K8s 리소스 정리 후 destroy
destroy: init _pre-destroy-hook
	@$(TF_STACK) destroy $(TF_VAR_FILES) $(TF_ARGS)

# Pre-destroy hook: 55-rancher 스택일 때만 K8s 리소스 정리
_pre-destroy-hook:
ifeq ($(STACK),55-rancher)
	@echo "==> [55-rancher] Pre-destroy cleanup: Helm releases and namespaces..."
	@helm uninstall rancher -n cattle-system 2>/dev/null || true
	@helm uninstall cert-manager -n cert-manager 2>/dev/null || true
	@kubectl delete namespace cattle-system --ignore-not-found --timeout=60s 2>/dev/null || true
	@kubectl delete namespace cert-manager --ignore-not-found --timeout=60s 2>/dev/null || true
	@kubectl delete crd -l app.kubernetes.io/name=cert-manager 2>/dev/null || true
	@echo "==> [55-rancher] Pre-destroy cleanup completed."
endif

refresh: init
	@$(TF_STACK) apply -refresh-only $(TF_VAR_FILES) $(TF_ARGS)

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