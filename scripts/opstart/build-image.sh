#!/bin/bash
# =============================================================================
# Opstart — 이미지 빌드 오케스트레이터
# 로컬에서 실행: 빌드 컨텍스트 → S3 → SSM → Harbor EC2 빌드/푸시
#
# Usage: build-image.sh <HARBOR_INSTANCE_ID> <HARBOR_HOST> <S3_BUCKET> <PROJECT_ROOT>
# =============================================================================
set -e

HARBOR_INSTANCE_ID=$1
HARBOR_HOST=$2
S3_BUCKET=$3
PROJECT_ROOT=$4

if [ -z "$HARBOR_INSTANCE_ID" ] || [ -z "$HARBOR_HOST" ]; then
  echo "ERROR: Harbor instance ID or host not found. Skipping image build."
  exit 0
fi

TAG=$(cd "$PROJECT_ROOT" && git rev-parse --short HEAD 2>/dev/null || echo "latest")

# ── Step 1: 빌드 컨텍스트 + 스크립트 → S3 업로드 ──
echo "▸ Step 1: Uploading build context + script to S3..."
cd "$PROJECT_ROOT"

tar czf /tmp/opstart-build-context.tar.gz \
  ops/dashboard/Dockerfile \
  ops/dashboard/.dockerignore \
  ops/dashboard/app.py \
  ops/dashboard/requirements.txt \
  ops/dashboard/templates/ \
  ops/dashboard/static/ \
  scripts/ \
  gitops-apps/ 2>/dev/null || \
tar czf /tmp/opstart-build-context.tar.gz \
  ops/dashboard/Dockerfile \
  ops/dashboard/.dockerignore \
  ops/dashboard/app.py \
  ops/dashboard/requirements.txt \
  ops/dashboard/templates/ \
  scripts/ \
  gitops-apps/ 2>/dev/null || \
tar czf /tmp/opstart-build-context.tar.gz \
  ops/dashboard/Dockerfile \
  ops/dashboard/app.py \
  ops/dashboard/requirements.txt \
  ops/dashboard/templates/ \
  scripts/

aws s3 cp /tmp/opstart-build-context.tar.gz "s3://$S3_BUCKET/tmp/opstart-build-context.tar.gz" --quiet
aws s3 cp scripts/opstart/build-remote.sh "s3://$S3_BUCKET/tmp/opstart-build.sh" --quiet
rm -f /tmp/opstart-build-context.tar.gz

# ── Step 2: SSM → Harbor EC2에서 빌드 ──
echo "▸ Step 2: Building image on Harbor EC2 ($HARBOR_INSTANCE_ID) via SSM..."

CMD_ID=$(aws ssm send-command \
  --instance-ids "$HARBOR_INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --timeout-seconds 300 \
  --parameters "{\"commands\":[\"aws s3 cp s3://$S3_BUCKET/tmp/opstart-build.sh /tmp/opstart-build.sh --quiet && chmod +x /tmp/opstart-build.sh && /tmp/opstart-build.sh $S3_BUCKET $HARBOR_HOST $TAG\"]}" \
  --query "Command.CommandId" \
  --output text)

echo "  SSM Command ID: $CMD_ID"

# ── Step 3: 결과 대기 (최대 120초) ──
s3_cleanup() {
  aws s3 rm "s3://$S3_BUCKET/tmp/opstart-build-context.tar.gz" --quiet 2>/dev/null || true
  aws s3 rm "s3://$S3_BUCKET/tmp/opstart-build.sh" --quiet 2>/dev/null || true
}

for i in $(seq 1 24); do
  STATUS=$(aws ssm get-command-invocation \
    --command-id "$CMD_ID" \
    --instance-id "$HARBOR_INSTANCE_ID" \
    --query "Status" --output text 2>/dev/null || echo "Pending")

  if [ "$STATUS" == "Success" ]; then
    echo "✓ Image build completed successfully!"
    aws ssm get-command-invocation \
      --command-id "$CMD_ID" \
      --instance-id "$HARBOR_INSTANCE_ID" \
      --query "StandardOutputContent" --output text
    s3_cleanup
    exit 0
  elif [ "$STATUS" == "Failed" ] || [ "$STATUS" == "Cancelled" ] || [ "$STATUS" == "TimedOut" ]; then
    echo "ERROR: SSM command $STATUS"
    aws ssm get-command-invocation \
      --command-id "$CMD_ID" \
      --instance-id "$HARBOR_INSTANCE_ID" \
      --query "StandardErrorContent" --output text
    s3_cleanup
    exit 1
  fi

  echo -n "."
  sleep 5
done

echo "ERROR: SSM command timed out after 120s"
s3_cleanup
exit 1
