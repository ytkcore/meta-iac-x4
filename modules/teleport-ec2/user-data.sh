#!/bin/bash
set -e

# 로그 설정
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo ">>> Teleport Installation Started..."

# 1. Install Teleport
# (Amazon Linux 2023 / 2 assumed based on Golden Image)
# If Ubuntu, commands might differ.
# Using generic install script for compatibility.

TELEPORT_VERSION="${teleport_version}"
# Install Teleport Repo
yum-config-manager --add-repo https://rpm.releases.teleport.dev/teleport.repo
yum install -y teleport-$TELEPORT_VERSION

# 2. Configure Teleport
# Using DynamoDB & S3 Backend
cat > /etc/teleport.yaml <<EOF
teleport:
  nodename: $(hostname)
  data_dir: /var/lib/teleport
  log:
    output: stderr
    severity: INFO
    format:
      output: text
  
  # Configure High Availability Storage (DynamoDB + S3)
  storage:
    type: dynamodb
    region: ${region}
    table_name: ${dynamo_table}
    audit_events_uri: "dynamodb://${dynamo_table}_audit"
    audit_sessions_uri: "s3://${s3_bucket}/records"
    continuous_backups: true

auth_service:
  enabled: "yes"
  cluster_name: "${cluster_name}"
  listen_addr: 0.0.0.0:3025
  
  # Public Address (for clients/nodes to reach auth service)
  # Should proveid Public DNS or ALB DNS if external access is needed
  # public_addr: "${cluster_name}:3025" 
  
  authentication:
    type: local
    second_factor: otp

ssh_service:
  enabled: "yes"
  labels:
    env: dev
    role: proxy
  commands:
  - name: hostname
    command: [hostname]
    period: 1m0s

proxy_service:
  enabled: "yes"
  listen_addr: 0.0.0.0:3023
  web_listen_addr: 0.0.0.0:3080
  tunnel_listen_addr: 0.0.0.0:3024
  public_addr: "${cluster_name}:443"  # ALB uses 443
  
  # TLS is handled by ALB (ACM) -> Proxy (HTTP or Self-signed HTTPS)
  # Here we terminate TLS at ALB, so Proxy can use HTTP or (better) Self-signed HTTPS.
  # Teleport requires HTTPS for Web UI even behind ALB mostly.
  https_keypairs: []
  
  # ACME (Let's Encrypt) is NOT used because we use ACM on ALB.
  acme:
    enabled: "no"

EOF

# 3. Create Audit Table for DynamoDB (if not exists, Teleport might create it but IAM perm allows it)
# The main table is created by Terraform, audit table is separate usually or same.
# We configured "audit_events_uri: dynamodb://..." which creates a separate table or index.

# 4. Start Teleport
systemctl enable teleport
systemctl start teleport

echo ">>> Teleport Installation Completed!"
