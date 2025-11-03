#!/bin/bash
# Script to install NGINX Proxy Manager on Ubuntu and run it on port 81

set -e  # Exit on any error

#  Install Docker & Docker Compose if missing
if ! command -v docker &>/dev/null; then
    echo "Docker not found. Installing Docker..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg lsb-release

    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
    echo "Docker is already installed."
fi

#  Create required directories
mkdir -p ~/nginx-proxy-manager/data
mkdir -p ~/nginx-proxy-manager/letsencrypt

#  Create docker-compose.yml
cat <<'EOF' > ~/nginx-proxy-manager/docker-compose.yml
version: '3'
services:
  app:
    image: jc21/nginx-proxy-manager:latest
    restart: unless-stopped
    ports:
      - "81:81"     # Admin Web UI
      - "80:80"     # HTTP proxy
      - "443:443"   # HTTPS proxy
    environment:
      DB_SQLITE_FILE: "/data/database.sqlite"
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
EOF

#  Launch NGINX Proxy Manager
cd ~/nginx-proxy-manager
sudo docker compose up -d
# Wait for all containers to become healthy
echo "⏳ Waiting for containers to become healthy..."

# Timeout in seconds
TIMEOUT=600
INTERVAL=5
ELAPSED=0

while [[ $(sudo docker ps --format '{{.Names}} {{.Status}}' | grep -c 'healthy') -lt $(sudo docker ps --format '{{.Names}}' | wc -l) ]]; do
    if (( ELAPSED >= TIMEOUT )); then
        echo "❌ Timeout reached. Some containers are not healthy."
        sudo docker ps
        exit 1
    fi

    echo "   ...still waiting ($(($ELAPSED))s / $TIMEOUT)s"
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo "✅ All containers are healthy!"

echo "NGINX Proxy Manager installed and running!"
echo "Admin interface: http://localhost:81"
echo "Default credentials: admin@example.com / changeme"
