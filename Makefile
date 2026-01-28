SHELL := /usr/bin/env bash

# -----------------------------------------------------------------------------
# Main Entry Point
# Repo: Terraform AWS Network Infrastructure
# -----------------------------------------------------------------------------

# 설정 및 공통 변수 로드 & 기능별 모듈 로드
include makefiles/config.mk
include makefiles/backend.mk
include makefiles/terraform.mk
include makefiles/qa.mk
include makefiles/utils.mk

.PHONY: help whoami

help:
	@echo '사용법:'
	@echo ''
	@echo '  (1) 초기 설정 & 백엔드:'
	@echo '      make env-init ENV=dev'
	@echo '      aws-vault exec <profile> -- make backend-bootstrap ENV=dev'
	@echo ''
	@echo '  (2) 테라폼 운영 (Plan/Apply):'
	@echo '      aws-vault exec <profile> -- make plan  ENV=dev STACK=00-network'
	@echo '      aws-vault exec <profile> -- make apply ENV=dev STACK=00-network'
	@echo '      aws-vault exec <profile> -- make apply ENV=dev STACK=50-rke2'
	@echo ''
	@echo '  (3) 조회 및 접속 (운영):'
	@echo '      make outputs ENV=dev                 # 전체 스택 현황판'
	@echo '      make output-50-rke2 ENV=dev          # 특정 스택 조회'
	@echo '      make kubeconfig ENV=dev              # K8s 접속 설정 자동 추출'
	@echo ''
	@echo '  (4) 품질 관리:'
	@echo '      make check       # 코드 포맷 검사'
	@echo '      make lint-all    # 전체 정적 분석'

whoami:
	@aws sts get-caller-identity