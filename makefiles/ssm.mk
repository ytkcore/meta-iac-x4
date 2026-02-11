# =============================================================================
# SSM Tunnel & Session Integration
# =============================================================================

.PHONY: tunnel-check tunnel-stop ssm-harbor harbor-tunnel harbor-push aipp-mirror gpu-stop gpu-start gpu-status

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

# -----------------------------------------------------------------------------
# SSM Session: Harbor EC2
# Usage: aws-vault exec devops -- make ssm-harbor ENV=dev
# -----------------------------------------------------------------------------
ssm-harbor:
	@echo "🔍 Resolving Harbor instance ID from Terraform state..."
	@INSTANCE_ID=$$(cd stacks/$(ENV)/40-harbor && \
		terraform output -raw instance_id 2>/dev/null) && \
	if [ -z "$$INSTANCE_ID" ]; then \
		echo "❌ Harbor instance ID not found. Is 40-harbor deployed?"; \
		exit 1; \
	fi && \
	echo "✓ Harbor EC2: $$INSTANCE_ID" && \
	echo "▸ Starting SSM session..." && \
	aws ssm start-session --target "$$INSTANCE_ID"

# -----------------------------------------------------------------------------
# SSM Port Forwarding: Harbor Registry (Docker Push from Mac)
# Usage: aws-vault exec devops -- make harbor-tunnel ENV=dev
# 터널 열린 후: docker login localhost:8880 && docker push localhost:8880/<project>/<image>:<tag>
# -----------------------------------------------------------------------------
HARBOR_LOCAL_PORT ?= 8880

harbor-tunnel:
	@echo "🔍 Resolving Harbor instance ID from Terraform state..."
	@INSTANCE_ID=$$(cd stacks/$(ENV)/40-harbor && \
		terraform output -raw instance_id 2>/dev/null) && \
	if [ -z "$$INSTANCE_ID" ]; then \
		echo "❌ Harbor instance ID not found. Is 40-harbor deployed?"; \
		exit 1; \
	fi && \
	echo "✓ Harbor EC2: $$INSTANCE_ID" && \
	echo "▸ Starting SSM port forwarding (Harbor :80 → localhost:$(HARBOR_LOCAL_PORT))..." && \
	echo "  docker login localhost:$(HARBOR_LOCAL_PORT) --username admin" && \
	echo "  docker tag <image> localhost:$(HARBOR_LOCAL_PORT)/<project>/<name>:<tag>" && \
	echo "  docker push localhost:$(HARBOR_LOCAL_PORT)/<project>/<name>:<tag>" && \
	echo "" && \
	aws ssm start-session \
		--target "$$INSTANCE_ID" \
		--document-name AWS-StartPortForwardingSession \
		--parameters '{"portNumber":["80"],"localPortNumber":["$(HARBOR_LOCAL_PORT)"]}'

# -----------------------------------------------------------------------------
# Harbor Image Mirror: Mac → S3 → Harbor EC2 (via SSM)
# Usage:
#   aws-vault exec devops -- make harbor-push ENV=dev IMAGE=registry.gitlab.../backend:latest TAG=aipp/backend:v1.0.0
#   aws-vault exec devops -- make harbor-push ENV=dev IMAGE=redis:7 TAG=aipp/redis:7 PROJECT=aipp
# -----------------------------------------------------------------------------
HARBOR_S3_PREFIX := tmp/opstart-mirror
HARBOR_PASS ?= $(shell grep 'admin_password' stacks/$(ENV)/env.tfvars 2>/dev/null | cut -d'"' -f2 || echo "")

harbor-push:
	@if [ -z "$(IMAGE)" ] || [ -z "$(TAG)" ]; then \
		echo "Usage: make harbor-push ENV=dev IMAGE=<source> TAG=<project/name:version> [HARBOR_PASS=xxx]"; \
		echo "  IMAGE : 로컬에 있는 소스 이미지 (docker images로 확인)"; \
		echo "  TAG   : Harbor 대상 태그 (예: aipp/backend:v1.0.0)"; \
		exit 1; \
	fi
	@if [ -z "$(HARBOR_PASS)" ]; then \
		echo "❌ HARBOR_PASS가 필요합니다. 사용법:"; \
		echo "   make harbor-push ... HARBOR_PASS=<harbor_admin_password>"; \
		exit 1; \
	fi
	@INSTANCE_ID=$$(cd stacks/$(ENV)/40-harbor && \
		terraform output -raw instance_id 2>/dev/null) && \
	BUCKET=$$(grep 'bucket' stacks/$(ENV)/backend.hcl | cut -d'"' -f2) && \
	if [ -z "$$INSTANCE_ID" ]; then \
		echo "❌ Harbor instance ID not found."; exit 1; \
	fi && \
	FILENAME=$$(echo "$(TAG)" | tr '/:' '-').tar && \
	if aws s3 ls "s3://$$BUCKET/$(HARBOR_S3_PREFIX)/$$FILENAME" >/dev/null 2>&1; then \
		echo "⏭️  Step 1-2/4: S3에 이미 존재 — save/upload 스킵"; \
	else \
		echo "📦 Step 1/4: Saving image $(IMAGE) → /tmp/$$FILENAME" && \
		docker save "$(IMAGE)" -o "/tmp/$$FILENAME" && \
		echo "☁️  Step 2/4: Uploading to S3 ($$BUCKET)..." && \
		aws s3 cp "/tmp/$$FILENAME" "s3://$$BUCKET/$(HARBOR_S3_PREFIX)/$$FILENAME" --quiet && \
		rm -f "/tmp/$$FILENAME"; \
	fi && \
	echo "🔨 Step 3/4: Loading & pushing on Harbor EC2 ($$INSTANCE_ID)..." && \
	CMD_ID=$$(aws ssm send-command \
		--instance-ids "$$INSTANCE_ID" \
		--document-name "AWS-RunShellScript" \
		--timeout-seconds 300 \
		--parameters "{\"commands\":[\"aws s3 cp s3://$$BUCKET/$(HARBOR_S3_PREFIX)/$$FILENAME /tmp/$$FILENAME --quiet && docker load -i /tmp/$$FILENAME && docker login localhost -u admin -p '$(HARBOR_PASS)' 2>/dev/null && docker tag $(IMAGE) localhost/$(TAG) && docker push localhost/$(TAG) && rm -f /tmp/$$FILENAME && echo DONE: localhost/$(TAG)\"]}" \
		--query "Command.CommandId" --output text) && \
	echo "  SSM Command: $$CMD_ID" && \
	for i in $$(seq 1 36); do \
		STATUS=$$(aws ssm get-command-invocation \
			--command-id "$$CMD_ID" --instance-id "$$INSTANCE_ID" \
			--query "Status" --output text 2>/dev/null || echo "Pending"); \
		if [ "$$STATUS" = "Success" ]; then \
			echo "✅ Step 4/4: Push 완료!" && \
			aws ssm get-command-invocation --command-id "$$CMD_ID" \
				--instance-id "$$INSTANCE_ID" --query "StandardOutputContent" --output text; \
			exit 0; \
		elif [ "$$STATUS" = "Failed" ] || [ "$$STATUS" = "TimedOut" ]; then \
			echo "❌ SSM command $$STATUS" && \
			aws ssm get-command-invocation --command-id "$$CMD_ID" \
				--instance-id "$$INSTANCE_ID" --query "StandardErrorContent" --output text; \
			exit 1; \
		fi; \
		printf "."; sleep 5; \
	done && \
	echo "❌ Timeout (180s)" && exit 1

# -----------------------------------------------------------------------------
# GPU Node Power Management (비용 절감)
# Usage:
#   aws-vault exec devops -- make gpu-stop   ENV=dev   # Stop (비용 중단)
#   aws-vault exec devops -- make gpu-start  ENV=dev   # Start (재사용)
#   aws-vault exec devops -- make gpu-status ENV=dev   # 상태 확인
# -----------------------------------------------------------------------------
gpu-stop:
	@INSTANCE_ID=$$(aws ec2 describe-instances \
		--filters "Name=tag:node.kubernetes.io/gpu,Values=true" \
		          "Name=tag:Env,Values=$(ENV)" \
		          "Name=instance-state-name,Values=running" \
		--query "Reservations[].Instances[].InstanceId" --output text) && \
	if [ -z "$$INSTANCE_ID" ]; then \
		echo "⚠️  실행 중인 GPU 노드 없음"; exit 0; \
	fi && \
	echo "⏹️  GPU 노드 정지: $$INSTANCE_ID" && \
	aws ec2 stop-instances --instance-ids $$INSTANCE_ID --output text && \
	echo "✅ Stop 요청 완료 (K8s에서 NotReady → Pod 자동 재스케줄링)"

gpu-start:
	@INSTANCE_ID=$$(aws ec2 describe-instances \
		--filters "Name=tag:node.kubernetes.io/gpu,Values=true" \
		          "Name=tag:Env,Values=$(ENV)" \
		          "Name=instance-state-name,Values=stopped" \
		--query "Reservations[].Instances[].InstanceId" --output text) && \
	if [ -z "$$INSTANCE_ID" ]; then \
		echo "⚠️  정지된 GPU 노드 없음"; exit 0; \
	fi && \
	echo "▶️  GPU 노드 시작: $$INSTANCE_ID" && \
	aws ec2 start-instances --instance-ids $$INSTANCE_ID --output text && \
	echo "✅ Start 요청 완료 (부팅 후 K8s 자동 조인, ~3분 소요)"

gpu-status:
	@echo "🔍 GPU 노드 상태:" && \
	aws ec2 describe-instances \
		--filters "Name=tag:node.kubernetes.io/gpu,Values=true" \
		          "Name=tag:Env,Values=$(ENV)" \
		--query "Reservations[].Instances[].{ID:InstanceId,Type:InstanceType,State:State.Name,IP:PrivateIpAddress}" \
		--output table

# -----------------------------------------------------------------------------
# AIPP Image Mirror: GitLab Registry → Harbor (일괄 처리)
# Usage: aws-vault exec devops -- make aipp-mirror ENV=dev HARBOR_PASS=xxx
# -----------------------------------------------------------------------------
AIPP_REGISTRY := registry.gitlab.enai-rnd-2.en-core.info:10003
AIPP_VERSION  ?= v1.0.0

AIPP_IMAGES := \
	enai/prod/front-next:latest=aipp/front-next:$(AIPP_VERSION) \
	enai/prod/backend:latest=aipp/backend:$(AIPP_VERSION) \
	enai/prod/catalog-collector:latest=aipp/catalog-collector:$(AIPP_VERSION) \
	enai/prod/linker:main-latest=aipp/linker:$(AIPP_VERSION) \
	enai/prod/scheduler:latest=aipp/scheduler:$(AIPP_VERSION)

aipp-mirror:
	@if [ -z "$(HARBOR_PASS)" ]; then \
		echo "Usage: make aipp-mirror ENV=dev HARBOR_PASS=<password> [AIPP_VERSION=v1.0.0]"; \
		exit 1; \
	fi
	@echo "🚀 AIPP 이미지 미러링 시작 ($(words $(AIPP_IMAGES))개)"
	@echo "   Registry: $(AIPP_REGISTRY) → Harbor (aipp/)"
	@echo "   Version:  $(AIPP_VERSION)"
	@echo ""
	@FAILED=0; \
	for PAIR in $(AIPP_IMAGES); do \
		SRC=$$(echo $$PAIR | cut -d= -f1); \
		DST=$$(echo $$PAIR | cut -d= -f2); \
		FULL_SRC=$(AIPP_REGISTRY)/$$SRC; \
		echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
		echo "📥 Pulling $$SRC"; \
		if docker pull $$FULL_SRC; then \
			echo "📤 Pushing → Harbor $$DST"; \
			$(MAKE) harbor-push ENV=$(ENV) IMAGE=$$FULL_SRC TAG=$$DST HARBOR_PASS=$(HARBOR_PASS) || FAILED=$$((FAILED+1)); \
		else \
			echo "❌ Pull 실패: $$SRC"; \
			FAILED=$$((FAILED+1)); \
		fi; \
		echo ""; \
	done; \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
	if [ $$FAILED -eq 0 ]; then \
		echo "✅ 전체 미러링 완료! ($(words $(AIPP_IMAGES))개)"; \
	else \
		echo "⚠️  $$FAILED개 실패. 실패한 이미지는 개별 harbor-push로 재시도하세요."; \
		exit 1; \
	fi
