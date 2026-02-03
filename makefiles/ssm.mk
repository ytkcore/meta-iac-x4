# =============================================================================
# SSM Tunnel Integration
# =============================================================================

.PHONY: tunnel-check tunnel-stop

# Conditional logic: Only check tunnel for stacks that need cluster access
NEED_TUNNEL_STACKS := 55-bootstrap 60-apps 99-gitops

# Check if current STACK is in the list
IS_TUNNEL_STACK = $(if $(filter $(STACK),$(NEED_TUNNEL_STACKS)),true,false)

kubeconfig-check:
	@if [ "$(IS_TUNNEL_STACK)" = "true" ]; then \
		echo "Checking Kubeconfig for $(STACK)..."; \
		./scripts/rke2/get-kubeconfig.sh || \
		(if [[ "$(MAKECMDGOALS)" =~ "destroy" ]]; then \
			echo "Warning: Cluster unreachable. Proceeding with destroy because cluster might be already gone."; \
		else \
			exit 1; \
		fi); \
	fi

tunnel-check: kubeconfig-check
	@if [ "$(IS_TUNNEL_STACK)" = "true" ]; then \
		./scripts/common/tunnel.sh start-bg "$(ENV)"; \
	fi

tunnel-stop:
	@./scripts/common/tunnel.sh stop "$(ENV)"
