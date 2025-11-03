#!/bin/bash
# Script to set up Authentik in Docker on a stock Ubuntu installation
# Run as root!

set -e  # Exit on error

# Add Docker's official GPG key
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker repository
source /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# Install Docker & Compose
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo systemctl enable docker; sudo systemctl start docker

# Generate .env file
cat <<EOF > .env
PG_DB=authentik
PG_USER=authentik
PG_PASS=$(openssl rand -base64 24)
AUTHENTIK_SECRET_KEY=$(openssl rand -base64 50)
EOF



# Create docker-compose.yml
cat <<'EOF' > docker-compose.yml
services:
  postgresql:
    env_file:
    - .env
    environment:
      POSTGRES_DB: ${PG_DB:-authentik}
      POSTGRES_PASSWORD: ${PG_PASS:?database password required}
      POSTGRES_USER: ${PG_USER:-authentik}
    healthcheck:
      interval: 30s
      retries: 5
      start_period: 20s
      test:
      - CMD-SHELL
      - pg_isready -d $${POSTGRES_DB} -U $${POSTGRES_USER}
      timeout: 5s
    image: docker.io/library/postgres:16-alpine
    restart: unless-stopped
    volumes:
    - database:/var/lib/postgresql/data
  redis:
    command: --save 60 1 --loglevel warning
    healthcheck:
      interval: 30s
      retries: 5
      start_period: 20s
      test:
      - CMD-SHELL
      - redis-cli ping | grep PONG
      timeout: 3s
    image: docker.io/library/redis:alpine
    restart: unless-stopped
    volumes:
    - redis:/data
  server:
    command: server
    depends_on:
      postgresql:
        condition: service_healthy
      redis:
        condition: service_healthy
    env_file:
    - .env
    environment:
      AUTHENTIK_POSTGRESQL__HOST: postgresql
      AUTHENTIK_POSTGRESQL__NAME: ${PG_DB:-authentik}
      AUTHENTIK_POSTGRESQL__PASSWORD: ${PG_PASS}
      AUTHENTIK_POSTGRESQL__USER: ${PG_USER:-authentik}
      AUTHENTIK_REDIS__HOST: redis
      AUTHENTIK_SECRET_KEY: ${AUTHENTIK_SECRET_KEY:?secret key required}
    image: ${AUTHENTIK_IMAGE:-ghcr.io/goauthentik/server}:${AUTHENTIK_TAG:-2025.8.1}
    ports:
    - ${COMPOSE_PORT_HTTP:-9000}:9000
    - ${COMPOSE_PORT_HTTPS:-9443}:9443
    restart: unless-stopped
    volumes:
    - ./media:/media
    - ./custom-templates:/templates
  worker:
    command: worker
    depends_on:
      postgresql:
        condition: service_healthy
      redis:
        condition: service_healthy
    env_file:
    - .env
    environment:
      AUTHENTIK_POSTGRESQL__HOST: postgresql
      AUTHENTIK_POSTGRESQL__NAME: ${PG_DB:-authentik}
      AUTHENTIK_POSTGRESQL__PASSWORD: ${PG_PASS}
      AUTHENTIK_POSTGRESQL__USER: ${PG_USER:-authentik}
      AUTHENTIK_REDIS__HOST: redis
      AUTHENTIK_SECRET_KEY: ${AUTHENTIK_SECRET_KEY:?secret key required}
    image: ${AUTHENTIK_IMAGE:-ghcr.io/goauthentik/server}:${AUTHENTIK_TAG:-2025.8.1}
    restart: unless-stopped
    user: root
    volumes:
    - /var/run/docker.sock:/var/run/docker.sock
    - ./media:/media
    - ./certs:/certs
    - ./custom-templates:/templates
volumes:
  database:
    driver: local
  redis:
    driver: local
EOF

echo "✅ Setup complete. You can now run: sudo docker compose up -d"

echo "PG_PASS=$(openssl rand -base64 36 | tr -d '\n')" >> .env
echo "AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')" >> .env

# Bring up containers
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

echo "Authentik is starting on Port 9000!" "Happy Proxying!"
echo "Please visit http://<your server's IP or hostname>:9000/if/flow/initial-setup/ to setup credentials!"
echo "with love <3 -- self hosted guy"
