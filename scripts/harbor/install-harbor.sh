#!/bin/bash
set -e
ENV="${1:-dev}"; NAME="${2:-harbor}"; VERSION="${3:-2.9.1}"
SSM_PARAM="/harbor/${ENV}/${NAME}/config/yaml"

echo "🚀 [Start] Harbor Deployment (Env: $ENV, Ver: $VERSION)"

# 1. Install Docker & Compose (Amazon Linux 2023)
if ! command -v docker &> /dev/null; then
    dnf update -y && dnf install -y docker python3 tar gzip openssl jq
    dnf install -y docker-compose-plugin || curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m) -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    echo -e '#!/bin/bash\nexec docker compose "$@"' > /usr/bin/docker-compose && chmod +x /usr/bin/docker-compose
    systemctl enable --now docker
fi

# 2. Download Harbor
mkdir -p /opt/harbor /data/harbor /data/cert; cd /opt/harbor
if [ ! -d "harbor" ]; then
    curl -fsSL -o harbor.tgz "https://github.com/goharbor/harbor/releases/download/v${VERSION}/harbor-online-installer-v${VERSION}.tgz"
    tar -xzf harbor.tgz
fi
cd harbor

# 3. Fetch Config from SSM (Decrypt SecureString)
echo "🔄 Fetching Config from SSM..."
aws ssm get-parameter --name "${SSM_PARAM}" --with-decryption --query "Parameter.Value" --output text > harbor.yml

# 4. Generate TLS Cert (If needed)
if grep -q "https:" harbor.yml && [ ! -f /data/cert/server.key ]; then
    echo "🔒 Generating Self-Signed Cert..."
    CN=$(grep 'hostname:' harbor.yml | awk '{print $2}')
    openssl req -x509 -nodes -newkey rsa:4096 -keyout /data/cert/server.key -out /data/cert/server.crt -days 3650 -subj "/CN=${CN}"
fi

# 5. Start Harbor
echo "✨ Apply Configuration & Restarting..."
docker compose down || true
./prepare
docker compose up -d

echo "✅ Harbor Deployed Successfully!"