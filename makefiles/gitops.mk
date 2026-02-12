# =============================================================================
# GitOps Application Deployment
# =============================================================================
# Landing Page, Platform Dashboard 등 ArgoCD 앱 배포 관리
#
# 사용법:
#   aws-vault exec devops -- make deploy-landing-page ENV=dev
#   aws-vault exec devops -- make deploy-dashboard ENV=dev
#   aws-vault exec devops -- make gitops-status ENV=dev
# =============================================================================

.PHONY: deploy-landing-page deploy-dashboard gitops-status gitops-sync gitops-cluster-check

# GitOps 전용 클러스터 접근 (STACK 무관하게 항상 실행)
gitops-cluster-check:
	@echo "🔑 Kubeconfig 확인..."
	@./scripts/rke2/get-kubeconfig.sh
	@echo "🔗 SSM Tunnel 확인..."
	@./scripts/common/tunnel.sh start-bg "$(ENV)"

# -----------------------------------------------------------------------------
# Landing Page: www.unifiedmeta.net
# Usage: aws-vault exec devops -- make deploy-landing-page ENV=dev
# -----------------------------------------------------------------------------
deploy-landing-page: gitops-cluster-check
	@echo "══════════════════════════════════════════════════════════"
	@echo "🚀 Landing Page 배포 (www.unifiedmeta.net)"
	@echo "══════════════════════════════════════════════════════════"
	@echo ""
	@echo "▸ Step 1/4: apps 네임스페이스 확인..."
	@kubectl get ns apps >/dev/null 2>&1 || kubectl create ns apps
	@echo "  ✓ Namespace 'apps' ready"
	@echo ""
	@echo "▸ Step 2/4: ArgoCD Application 등록..."
	@kubectl apply -f gitops-apps/bootstrap/landing-page.yaml
	@echo "  ✓ ArgoCD Application 'landing-page' applied"
	@echo ""
	@echo "▸ Step 3/4: ArgoCD Sync 대기 (최대 2분)..."
	@for i in $$(seq 1 24); do \
		HEALTH=$$(kubectl get application landing-page -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown"); \
		SYNC=$$(kubectl get application landing-page -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown"); \
		if [ "$$HEALTH" = "Healthy" ] && [ "$$SYNC" = "Synced" ]; then \
			echo "  ✓ ArgoCD: Health=$$HEALTH, Sync=$$SYNC"; \
			break; \
		fi; \
		printf "  ⏳ Health=$$HEALTH, Sync=$$SYNC ($$i/24)...\n"; \
		sleep 5; \
	done
	@echo ""
	@echo "▸ Step 4/4: Pod 상태 확인..."
	@kubectl get pods -n apps -l app=landing-page -o wide 2>/dev/null || echo "  ⚠️  Pod 아직 생성 중..."
	@echo ""
	@echo "══════════════════════════════════════════════════════════"
	@echo "✅ Landing Page 배포 완료!"
	@echo ""
	@echo "📋 확인 사항:"
	@echo "   1. DNS: www.unifiedmeta.net → NLB (ExternalDNS 자동 또는 Route53 수동)"
	@echo "   2. TLS: kubectl get certificate -n apps landing-page-tls"
	@echo "   3. 접속: https://www.unifiedmeta.net"
	@echo "══════════════════════════════════════════════════════════"

# -----------------------------------------------------------------------------
# Platform Dashboard: dashboard.unifiedmeta.net
# Usage: aws-vault exec devops -- make deploy-dashboard ENV=dev
# -----------------------------------------------------------------------------
deploy-dashboard: gitops-cluster-check
	@echo "══════════════════════════════════════════════════════════"
	@echo "🚀 Platform Dashboard 배포 (dashboard.unifiedmeta.net)"
	@echo "══════════════════════════════════════════════════════════"
	@echo ""
	@echo "▸ Step 1/4: apps 네임스페이스 확인..."
	@kubectl get ns apps >/dev/null 2>&1 || kubectl create ns apps
	@echo "  ✓ Namespace 'apps' ready"
	@echo ""
	@echo "▸ Step 2/4: ArgoCD Application 등록..."
	@kubectl apply -f gitops-apps/bootstrap/platform-dashboard.yaml
	@echo "  ✓ ArgoCD Application 'platform-dashboard' applied"
	@echo ""
	@echo "▸ Step 3/4: ArgoCD Sync 대기 (최대 2분)..."
	@for i in $$(seq 1 24); do \
		HEALTH=$$(kubectl get application platform-dashboard -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown"); \
		SYNC=$$(kubectl get application platform-dashboard -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown"); \
		if [ "$$HEALTH" = "Healthy" ] && [ "$$SYNC" = "Synced" ]; then \
			echo "  ✓ ArgoCD: Health=$$HEALTH, Sync=$$SYNC"; \
			break; \
		fi; \
		printf "  ⏳ Health=$$HEALTH, Sync=$$SYNC ($$i/24)...\n"; \
		sleep 5; \
	done
	@echo ""
	@echo "▸ Step 4/4: Pod 상태 확인..."
	@kubectl get pods -n apps -l app=platform-dashboard -o wide 2>/dev/null || echo "  ⚠️  Pod 아직 생성 중..."
	@echo ""
	@echo "══════════════════════════════════════════════════════════"
	@echo "✅ Platform Dashboard 배포 완료!"
	@echo ""
	@echo "📋 확인 사항:"
	@echo "   1. DNS: dashboard.unifiedmeta.net → NLB"
	@echo "   2. TLS: kubectl get certificate -n apps platform-dashboard-tls"
	@echo "   3. 접속: https://dashboard.unifiedmeta.net"
	@echo "══════════════════════════════════════════════════════════"

# -----------------------------------------------------------------------------
# GitOps Status: 전체 ArgoCD Application 상태 확인
# Usage: aws-vault exec devops -- make gitops-status ENV=dev
# -----------------------------------------------------------------------------
gitops-status: gitops-cluster-check
	@echo "══════════════════════════════════════════════════════════"
	@echo "📊 ArgoCD Application 상태"
	@echo "══════════════════════════════════════════════════════════"
	@kubectl get applications -n argocd \
		-o custom-columns="NAME:.metadata.name,HEALTH:.status.health.status,SYNC:.status.sync.status,REPO:.spec.source.repoURL,PATH:.spec.source.path" \
		2>/dev/null || echo "⚠️  ArgoCD 앱 조회 실패. argocd 네임스페이스를 확인하세요."
	@echo ""

# -----------------------------------------------------------------------------
# GitOps Sync: 특정 앱 수동 동기화
# Usage: aws-vault exec devops -- make gitops-sync APP=landing-page ENV=dev
# -----------------------------------------------------------------------------
APP ?= landing-page

gitops-sync: gitops-cluster-check
	@echo "🔄 Syncing ArgoCD Application: $(APP)..."
	@kubectl patch application $(APP) -n argocd --type merge \
		-p '{"operation":{"initiatedBy":{"username":"make-cli"},"sync":{"revision":"HEAD"}}}' \
		2>/dev/null && echo "✓ Sync 요청 완료" \
		|| echo "⚠️  kubectl patch 실패. ArgoCD CLI(argocd app sync $(APP))를 사용하세요."
