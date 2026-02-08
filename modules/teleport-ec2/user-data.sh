#!/bin/bash
# Teleport EC2 Installation Script
# Version: 2026-02-04

set -euo pipefail

# 로그 설정
LOG_FILE="/var/log/user-data.log"
exec > >(tee "$LOG_FILE"|logger -t user-data -s 2>/dev/console) 2>&1

echo "=============================================="
echo ">>> Teleport Installation Started: $(date)"
echo "=============================================="

# 변수 확인
TELEPORT_VERSION="${teleport_version}"
CLUSTER_NAME="${cluster_name}"
REGION="${region}"
DYNAMO_TABLE="${dynamo_table}"
S3_BUCKET="${s3_bucket}"

echo ">>> Configuration:"
echo "    - Teleport Version: $TELEPORT_VERSION"
echo "    - Cluster Name: $CLUSTER_NAME"
echo "    - Region: $REGION"
echo "    - DynamoDB Table: $DYNAMO_TABLE"
echo "    - S3 Bucket: $S3_BUCKET"

# 1. Install Teleport
echo ">>> Step 1: Installing Teleport..."

# yum-config-manager 설치 확인 (Amazon Linux 2023)
if ! command -v yum-config-manager &> /dev/null; then
    echo ">>> Installing yum-utils for yum-config-manager..."
    yum install -y yum-utils
fi

# Teleport 저장소 추가
echo ">>> Adding Teleport repository..."
yum-config-manager --add-repo https://rpm.releases.teleport.dev/teleport.repo || {
    echo "ERROR: Failed to add Teleport repository"
    exit 1
}

# AL2023 vs AL2 감지 및 설치
echo ">>> Installing teleport-$TELEPORT_VERSION..."
if grep -q "Amazon Linux 2023" /etc/os-release 2>/dev/null; then
    echo ">>> Detected Amazon Linux 2023"
    dnf install -y teleport-"$TELEPORT_VERSION" || {
        echo "Standard install failed, trying direct RPM download..."
        wget -q https://cdn.teleport.dev/teleport-"$TELEPORT_VERSION"-1.x86_64.rpm
        dnf install -y ./teleport-"$TELEPORT_VERSION"-1.x86_64.rpm
    }
else
    yum install -y teleport-"$TELEPORT_VERSION" || {
        echo "ERROR: Failed to install Teleport"
        exit 1
    }
fi

# 설치 확인
if ! command -v teleport &> /dev/null; then
    echo "ERROR: Teleport binary not found after installation!"
    exit 1
fi
echo ">>> Teleport installed: $(teleport version)"

# 2. 데이터 디렉토리 준비
echo ">>> Step 2: Preparing data directory..."
mkdir -p /var/lib/teleport
mkdir -p /var/lib/teleport/audit/events
chmod 700 /var/lib/teleport
chmod -R 700 /var/lib/teleport/audit

# 3. Configure Teleport
echo ">>> Step 3: Creating Teleport configuration..."
cat > /etc/teleport.yaml <<EOF
version: v3
teleport:
  nodename: $(hostname)
  data_dir: /var/lib/teleport
  log:
    output: stderr
    severity: INFO
    format:
      output: text
  
  # High Availability Storage (DynamoDB + S3)
  storage:
    type: dynamodb
    region: $REGION
    table_name: $DYNAMO_TABLE
    audit_sessions_uri: "s3://$S3_BUCKET/records"
    audit_events_uri: "file:///var/lib/teleport/audit/events"
    continuous_backups: true

auth_service:
  enabled: "yes"
  cluster_name: "$CLUSTER_NAME"
  listen_addr: 0.0.0.0:3025
  
  authentication:
    type: local
    second_factor: otp

ssh_service:
  enabled: "yes"
  labels:
    env: ${environment}
    role: teleport-server

proxy_service:
  enabled: "yes"
  listen_addr: 0.0.0.0:3023
  web_listen_addr: 0.0.0.0:3080
  tunnel_listen_addr: 0.0.0.0:3024
  public_addr: "$CLUSTER_NAME:443"
  ssh_public_addr: "$CLUSTER_NAME:443"
  tunnel_public_addr: $(hostname):3024
  https_keypairs: []
  acme:
    enabled: "no"

app_service:
  enabled: "yes"
  apps:
    - name: harbor
      uri: https://harbor.${base_domain}
      insecure_skip_verify: true
      labels:
        env: ${environment}

EOF

echo ">>> Configuration file created at /etc/teleport.yaml"

# 3-1. Validate Configuration
echo ">>> Validating Teleport configuration..."
teleport configure --test -c /etc/teleport.yaml || {
  echo "WARNING: Teleport configuration validation failed (may be normal for first run)"
}

# 4. Start Teleport
echo ">>> Step 4: Starting Teleport service..."
systemctl daemon-reload
systemctl enable teleport
systemctl start teleport

# 5. 시작 확인 (최대 30초 대기)
echo ">>> Step 5: Verifying Teleport startup..."
for i in {1..6}; do
    if systemctl is-active --quiet teleport; then
        echo ">>> Teleport service is running!"
        break
    fi
    echo ">>> Waiting for Teleport to start... ($i/6)"
    sleep 5
done

# 최종 상태 확인
if systemctl is-active --quiet teleport; then
    echo "=============================================="
    echo ">>> Teleport Installation COMPLETED: $(date)"
    echo ">>> host_uuid: $(cat /var/lib/teleport/host_uuid 2>/dev/null || echo 'generating...')"
    echo "=============================================="
else
    echo "=============================================="
    echo ">>> ERROR: Teleport failed to start!"
    echo ">>> Check logs with: journalctl -u teleport -n 100"
    echo "=============================================="
    journalctl -u teleport -n 50 --no-pager
    exit 1
fi
