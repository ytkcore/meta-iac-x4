#!/usr/bin/env bash
# DEPRECATED: 더 이상 사용하지 않습니다.
# - 초기 배포 시 실행권한(chmod) 혼동을 줄이기 위해 Makefile의 versions-gen 타깃에서 직접 versions.tf를 동기화합니다.
# - 필요 시 참고용으로만 남겨둡니다.
set -euo pipefail
echo "DEPRECATED: use 'make versions-gen' instead."
exit 0
