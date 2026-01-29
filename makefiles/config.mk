# -----------------------------------------------------------------------------
# Configuration & Variables
# -----------------------------------------------------------------------------

# 사용자 입력 변수 (기본값 설정)
ENV   ?= dev
STACK ?= 00-network

# 디렉토리 및 템플릿 경로
STACK_DIR := stacks/$(ENV)/$(STACK)
BOOT_DIR  := stacks/bootstrap-backend
VERSIONS_TEMPLATE ?= templates/versions.tf

# Terraform Provider Cache (Local)
# - 플러그인 다운로드 시간을 단축하고 디스크 공간을 절약합니다.
# - 기본 경로: ~/.terraform.d/plugin-cache
export TF_PLUGIN_CACHE_DIR ?= $(HOME)/.terraform.d/plugin-cache

# 캐시 디렉토리가 없으면 생성 (shell 함수의 부작용을 이용)
_ := $(shell mkdir -p $(TF_PLUGIN_CACHE_DIR))

# Terraform 옵션
TF_OPTS ?= -compact-warnings
# 상위 디렉토리의 env.tfvars 참조
ENV_TFVARS := -var-file=../env.tfvars


# stacks/<env>/env.auto.tfvars (자동 생성/우선 적용)
ENV_AUTO_TFVARS := $(if $(wildcard stacks/$(ENV)/env.auto.tfvars),-var-file=../env.auto.tfvars,)

# Terraform 실행 래퍼 (디렉토리 이동 포함)
TF_STACK := terraform -chdir=$(STACK_DIR)
TF_BOOT  := terraform -chdir=$(BOOT_DIR)

# Backend configuration is managed via stacks/<env>/backend.hcl
# No Makefile variables needed - Terraform reads .hcl directly
BACKEND_CONFIG_FILE := stacks/$(ENV)/backend.hcl
STATE_KEY_PREFIX := iac

# 스택 실행 순서 및 RKE2 스택 이름 정의

STACK_ORDER := 00-network 10-security 20-endpoints 30-db 40-bastion 50-rke2 55-bootstrap 60-db
RKE2_STACK_NAME := 50-rke2