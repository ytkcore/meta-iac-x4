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

# Terraform 옵션
TF_ARGS ?= -compact-warnings
# 상위 디렉토리의 env.tfvars 참조
ENV_TFVARS := -var-file=../env.tfvars


# stacks/<env>/env.auto.tfvars (자동 생성/우선 적용)
ENV_AUTO_TFVARS := $(if $(wildcard stacks/$(ENV)/env.auto.tfvars),-var-file=../env.auto.tfvars,)

# Terraform 실행 래퍼 (디렉토리 이동 포함)
TF_STACK := terraform -chdir=$(STACK_DIR)
TF_BOOT  := terraform -chdir=$(BOOT_DIR)

# Remote Backend 설정 (기본값)
STATE_REGION     := $(or $(STATE_REGION),ap-northeast-2)
STATE_BUCKET     := $(or $(STATE_BUCKET),enc-tfstate)
STATE_KEY_PREFIX := $(or $(STATE_KEY_PREFIX),enc-iac)

# stacks/<env>/env.tfvars 파일이 존재하면 파싱하여 변수 덮어쓰기
ifneq (,$(wildcard stacks/$(ENV)/env.tfvars))
STATE_BUCKET     := $(or $(shell sed -nE 's/^\s*state_bucket\s*=\s*"([^"]+)".*/\1/p' stacks/$(ENV)/env.tfvars | head -n 1),$(STATE_BUCKET))
STATE_REGION     := $(or $(shell sed -nE 's/^\s*state_region\s*=\s*"([^"]+)".*/\1/p' stacks/$(ENV)/env.tfvars | head -n 1),$(STATE_REGION))
STATE_KEY_PREFIX := $(or $(shell sed -nE 's/^\s*state_key_prefix\s*=\s*"([^"]+)".*/\1/p' stacks/$(ENV)/env.tfvars | head -n 1),$(STATE_KEY_PREFIX))
endif

# 스택 실행 순서 및 RKE2 스택 이름 정의
STACK_ORDER := 00-network 10-security 20-endpoints 30-db 40-bastion 50-rke2 60-db
RKE2_STACK_NAME := 50-rke2