# -----------------------------------------------------------------------------
# Code Quality
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