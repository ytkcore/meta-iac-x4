#!/bin/bash
# =============================================================================
# Opstart — Harbor EC2 원격 빌드 스크립트
# SSM send-command로 Harbor EC2에서 실행됨
#
# Usage: build-remote.sh <S3_BUCKET> <HARBOR_HOST> <TAG>
# =============================================================================
set -e
echo "=== Opstart Image Build on Harbor EC2 ==="

S3_BUCKET=$1
HARBOR_HOST=$2
TAG=$3

BUILD_DIR=/tmp/opstart-build
rm -rf $BUILD_DIR && mkdir -p $BUILD_DIR

echo "Downloading build context from S3..."
aws s3 cp "s3://$S3_BUCKET/tmp/opstart-build-context.tar.gz" /tmp/opstart-build-context.tar.gz --quiet
tar xzf /tmp/opstart-build-context.tar.gz -C $BUILD_DIR
cd $BUILD_DIR

IMAGE="$HARBOR_HOST/platform/opstart"
echo "Building $IMAGE:$TAG"
docker build -t "$IMAGE:$TAG" -t "$IMAGE:latest" -f ops/dashboard/Dockerfile .

echo "Pushing to Harbor..."
docker push "$IMAGE:$TAG"
docker push "$IMAGE:latest"

# 정리
rm -rf $BUILD_DIR /tmp/opstart-build-context.tar.gz /tmp/opstart-build.sh
echo "✓ Opstart image pushed: $IMAGE:$TAG"
