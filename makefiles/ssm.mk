# =============================================================================
# SSM Tunnel Integration
# =============================================================================

.PHONY: tunnel-check tunnel-stop

# Conditional logic: Only check tunnel for stacks that need cluster access
NEED_TUNNEL_STACKS := 55-bootstrap 60-apps 99-gitops

# Check if current STACK is in the list
IS_TUNNEL_STACK = $(if $(filter $(STACK),$(NEED_TUNNEL_STACKS)),true,false)

tunnel-check:
	@if [ "$(IS_TUNNEL_STACK)" = "true" ]; then \
		./scripts/common/tunnel.sh start-bg "$(ENV)"; \
	fi

tunnel-stop:
	@./scripts/common/tunnel.sh stop "$(ENV)"
