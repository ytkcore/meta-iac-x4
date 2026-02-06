#!/bin/bash
set -e

# Log setup
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo ">>> Teleport Installation Started..."

# 1. Install Teleport
TELEPORT_VERSION="${teleport_version}"
# Check if running on Amazon Linux 2023 or 2
if grep -q "Amazon Linux 2023" /etc/os-release; then
  echo "Detected Amazon Linux 2023"
  # AL2023 often needs manual RPM install for specific versions or dnf config
  yum-config-manager --add-repo https://rpm.releases.teleport.dev/teleport.repo
  dnf install -y teleport-$TELEPORT_VERSION || {
       echo "Standard install failed, trying direct RPM download..."
       wget https://cdn.teleport.dev/teleport-$TELEPORT_VERSION-1.x86_64.rpm
       dnf install -y ./teleport-$TELEPORT_VERSION-1.x86_64.rpm
  }
else
  # AL2
  yum-config-manager --add-repo https://rpm.releases.teleport.dev/teleport.repo
  yum install -y teleport-$TELEPORT_VERSION
fi

# 2. Pre-create Data Directory
mkdir -p /var/lib/teleport
chown teleport:teleport /var/lib/teleport

# 3. Configure Teleport
cat > /etc/teleport.yaml <<EOF
teleport:
  nodename: $(hostname)
  data_dir: /var/lib/teleport
  log:
    output: stderr
    severity: INFO
  
  storage:
    type: dynamodb
    region: ${region}
    table_name: ${dynamo_table}
    audit_sessions_uri: "s3://${s3_bucket}/records"
    continuous_backups: true

auth_service:
  enabled: "yes"
  cluster_name: "${cluster_name}"
  listen_addr: 0.0.0.0:3025
  
  authentication:
    type: local
    second_factor: otp

ssh_service:
  enabled: "yes"
  labels:
    env: dev
    role: teleport-server

proxy_service:
  enabled: "yes"
  web_listen_addr: 0.0.0.0:3080
  tunnel_listen_addr: 0.0.0.0:3024
  public_addr: "${cluster_name}:443"
  ssh_public_addr: "${cluster_name}:443"
  tunnel_public_addr: $(hostname):3024
  
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

# 4. Validate Configuration
echo ">>> Validating Teleport configuration..."
teleport configure --test -c /etc/teleport.yaml || {
  echo "ERROR: Teleport configuration validation failed!"
  exit 1
}

# 5. Start Teleport
echo ">>> Starting Teleport service..."
systemctl enable teleport
systemctl start teleport

# 6. Wait and Verify
echo ">>> Waiting for Teleport to initialize..."
sleep 10

if systemctl is-active --quiet teleport; then
  echo ">>> Teleport started successfully!"
else
  echo "ERROR: Teleport failed to start!"
  journalctl -u teleport -n 50 --no-pager
  exit 1
fi

echo ">>> Teleport Installation Completed!"
