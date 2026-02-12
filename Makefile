SHELL := /usr/bin/env bash

# =============================================================================
# Terraform IaC - Main Entry Point
# =============================================================================

include makefiles/config.mk
include makefiles/ssm.mk
include makefiles/terraform.mk
include makefiles/utils.mk
include makefiles/packer.mk
include makefiles/gitops.mk

.PHONY: help whoami init credentials credentials-show smoke-test

init:
	@scripts/common/init-env.sh

check-ami:
	@scripts/common/check-ami.sh

build-ami:
	@chmod +x scripts/common/build-ami.sh
	@scripts/common/build-ami.sh

status:
	@scripts/common/check-status.sh $(ENV) $(STACK)

opstart:
	@scripts/common/opstart.sh

opstart-ui:
	@echo "Opstart Dashboard (β) — kubectl port-forward"
	@kubectl port-forward svc/opstart -n opstart 8080:8080

credentials:
	@scripts/common/credentials.sh

credentials-show:
	@scripts/common/credentials.sh --show

smoke-test:
	@scripts/common/smoke-test.sh

opstart-build:
	@echo "Opstart Docker 이미지 빌드 & 푸시"
	@docker build -t harbor.dev.unifiedmeta.net/platform/opstart:$$(git rev-parse --short HEAD) \
		-t harbor.dev.unifiedmeta.net/platform/opstart:latest \
		-f ops/dashboard/Dockerfile .
	@docker push harbor.dev.unifiedmeta.net/platform/opstart:$$(git rev-parse --short HEAD)
	@docker push harbor.dev.unifiedmeta.net/platform/opstart:latest

help:
	@echo 'Usage:'
	@echo ''
	@echo '  (1) Initial Setup:'
	@echo '      aws-vault exec <profile> -- make init ENV=dev'
	@echo ''
	@echo '  (2) Terraform Operations:'
	@echo '      make plan  ENV=dev STACK=00-network'
	@echo '      make apply ENV=dev STACK=00-network'
	@echo '      make status ENV=dev STACK=00-network'
	@echo ''
	@echo '  (3) GitOps Deploy:'
	@echo '      make deploy-landing-page ENV=dev  # 랜딩 페이지 배포'
	@echo '      make deploy-dashboard ENV=dev     # 플랫폼 대시보드 배포'
	@echo '      make gitops-status ENV=dev        # ArgoCD 앱 상태 확인'
	@echo '      make gitops-sync APP=xxx ENV=dev  # 수동 동기화'
	@echo ''
	@echo '  (4) Post-Deployment:'
	@echo '      make opstart           # 배포 후 운영 초기화 (6단계 CLI)'
	@echo '      make opstart-ui        # 운영 대시보드 접속 (β, port-forward)'
	@echo '      make credentials       # 초기 비밀번호 조회 명령어 출력'
	@echo '      make credentials-show  # 초기 비밀번호 실제 값 출력'
	@echo '      make smoke-test        # 전체 서비스 헬스체크'
	@echo ''
	@echo '  (5) Code Quality:'
	@echo '      make check       # Format check'
	@echo '      make lint-all    # Static analysis'
	@echo '      make clean       # Clean artifacts'

whoami:
	@aws sts get-caller-identity