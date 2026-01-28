# -----------------------------------------------------------------------------
# Backend Management
# -----------------------------------------------------------------------------
.PHONY: backend-bootstrap backend-destroy

backend-bootstrap: versions-gen
	@STATE_BUCKET="$(STATE_BUCKET)" STATE_REGION="$(STATE_REGION)" ./scripts/backend-bootstrap.sh

backend-destroy: versions-gen
	@if [ "$(FORCE)" != "1" ]; then \
	  echo "ERROR: 정말 삭제하려면 FORCE=1을 지정하세요."; \
	  exit 2; \
	fi
	@$(TF_BOOT) init -upgrade=false -reconfigure
	@$(TF_BOOT) destroy -auto-approve \
	  -var="state_bucket=$(STATE_BUCKET)" \
	  -var="state_region=$(STATE_REGION)"