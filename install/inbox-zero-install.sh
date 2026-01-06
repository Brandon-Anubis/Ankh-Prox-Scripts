#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: Brandon-Anubis (Adapted)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/elie222/inbox-zero

# Fallback if FUNCTIONS_FILE_PATH is not set or empty
if [ -z "$FUNCTIONS_FILE_PATH" ]; then
  export BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/Brandon-Anubis/Ankh-Prox-Scripts/main}"
  FUNCTIONS_FILE_PATH="$(curl -fsSL "${BASE_URL}"/misc/install.func)"
fi

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y curl git mc
msg_ok "Installed Dependencies"

get_latest_release() {
  curl -fsSL https://api.github.com/repos/"$1"/releases/latest | grep '"tag_name":' | cut -d'"' -f4
}

DOCKER_LATEST_VERSION=$(get_latest_release "moby/moby")
DOCKER_COMPOSE_LATEST_VERSION=$(get_latest_release "docker/compose")

msg_info "Installing Docker $DOCKER_LATEST_VERSION"
DOCKER_CONFIG_PATH='/etc/docker/daemon.json'
mkdir -p "$(dirname "$DOCKER_CONFIG_PATH")"
echo -e '{\n  "log-driver": "journald"\n}' >/etc/docker/daemon.json
$STD sh <(curl -fsSL https://get.docker.com)
msg_ok "Installed Docker $DOCKER_LATEST_VERSION"

msg_info "Installing Docker Compose $DOCKER_COMPOSE_LATEST_VERSION"
DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
mkdir -p "$DOCKER_CONFIG"/cli-plugins
curl -fsSL https://github.com/docker/compose/releases/download/"$DOCKER_COMPOSE_LATEST_VERSION"/docker-compose-linux-x86_64 -o ~/.docker/cli-plugins/docker-compose
chmod +x "$DOCKER_CONFIG"/cli-plugins/docker-compose
msg_ok "Installed Docker Compose $DOCKER_COMPOSE_LATEST_VERSION"

msg_info "Installing Inbox Zero"
mkdir -p /opt/inbox-zero
cd /opt/inbox-zero || exit

# Get container IP address
IP=$(hostname -I | awk '{print $1}')

# ---------------------------------------------------------------------------------
# Prerequisites Check
# ---------------------------------------------------------------------------------
echo ""
echo -e "${INFO}${YW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
echo -e "${INFO}${YW} PREREQUISITES INFORMATION${CL}"
echo -e "${INFO}${YW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
echo -e "${INFO}${YW} Inbox Zero requires OAuth credentials to function.${CL}"
echo -e "${INFO}${YW} You will need to set up ONE of the following:${CL}"
echo ""
echo -e "${INFO}${GN} Option 1: Google OAuth (Recommended)${CL}"
echo -e "${TAB}${GATEWAY}${BGN}https://console.cloud.google.com/${CL}"
echo -e "${TAB}• Create a new project or select existing"
echo -e "${TAB}• Enable Gmail API"
echo -e "${TAB}• Create OAuth 2.0 credentials"
echo -e "${TAB}• Add redirect URI: ${BGN}http://${IP}:3000/api/auth/callback/google${CL}"
echo ""
echo -e "${INFO}${GN} Option 2: Microsoft Azure AD${CL}"
echo -e "${TAB}${GATEWAY}${BGN}https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade${CL}"
echo -e "${TAB}• Register a new application"
echo -e "${TAB}• Add redirect URI: ${BGN}http://${IP}:3000/api/auth/callback/azure-ad${CL}"
echo ""
echo -e "${INFO}${YW} Optional: AI Features (Ollama)${CL}"
echo -e "${TAB}${GATEWAY}${BGN}https://ollama.ai/${CL}"
echo -e "${TAB}• Install Ollama on a GPU-enabled host"
echo -e "${TAB}• Set OLLAMA_HOST=0.0.0.0 in service config"
echo -e "${TAB}• Pull a model: ${BGN}ollama pull llama3${CL}"
echo ""
echo -e "${INFO}${YW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
echo ""
read -r -p "${TAB3}Have you obtained OAuth credentials? (Installation will continue, but login will fail without them) <y/N> " prereq_prompt
if [[ ! ${prereq_prompt,,} =~ ^(y|yes)$ ]]; then
  echo -e "${INFO}${RD} Note: You can configure OAuth later by editing /opt/inbox-zero/.env${CL}"
  echo -e "${INFO}${RD} The application will not be usable until OAuth is configured.${CL}"
  sleep 3
fi

# Generate secure passwords
POSTGRES_PASSWORD=$(openssl rand -base64 24)
NEXTAUTH_SECRET=$(openssl rand -base64 32)
EMAIL_ENCRYPT_SALT=$(openssl rand -hex 16)

# ---------------------------------------------------------------------------------
# Generate Docker Compose
# ---------------------------------------------------------------------------------
cat <<'EOF' > docker-compose.yml
version: '3.8'

services:
  web:
    image: ghcr.io/elie222/inbox-zero:latest
    container_name: inbox-zero
    ports:
      - "3000:3000"
    env_file: .env
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
    restart: always
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:3000/api/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    # Map extra hosts if you need to reach the host via host.docker.internal
    extra_hosts:
      - "host.docker.internal:host-gateway"

  db:
    image: postgres:15-alpine
    container_name: inbox-zero-db
    env_file: .env
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: inboxzero
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: always
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d inboxzero"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s

  redis:
    image: redis:alpine
    container_name: inbox-zero-redis
    restart: always
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 3

volumes:
  postgres_data:
EOF

# ---------------------------------------------------------------------------------
# Generate .env File with Placeholders
# ---------------------------------------------------------------------------------
# We use placeholders that stand out so the user knows to change them
cat <<EOF > .env
# ------------------------------------------------------------------------------
# CORE CONFIGURATION
# ------------------------------------------------------------------------------
NODE_ENV=production
NEXT_PUBLIC_APP_URL=http://${IP}:3000
NEXTAUTH_URL=http://${IP}:3000
NEXTAUTH_SECRET=${NEXTAUTH_SECRET}
EMAIL_ENCRYPT_SALT=${EMAIL_ENCRYPT_SALT}

# Database & Redis (Internal Docker Network)
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
DATABASE_URL=postgresql://postgres:${POSTGRES_PASSWORD}@db:5432/inboxzero
DIRECT_URL=postgresql://postgres:${POSTGRES_PASSWORD}@db:5432/inboxzero
REDIS_URL=redis://redis:6379

# ------------------------------------------------------------------------------
# OAUTH PROVIDERS (REQUIRED)
# ------------------------------------------------------------------------------
# Google Cloud Console: https://console.cloud.google.com/
# Redirect URI: http://${IP}:3000/api/auth/callback/google
GOOGLE_CLIENT_ID=change_me_google_client_id
GOOGLE_CLIENT_SECRET=change_me_google_client_secret

# Microsoft Azure: https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade
# Redirect URI: http://${IP}:3000/api/auth/callback/azure-ad
# AZURE_AD_CLIENT_ID=
# AZURE_AD_CLIENT_SECRET=
# AZURE_AD_TENANT_ID=

# ------------------------------------------------------------------------------
# AI CONFIGURATION (Ollama / Local AI)
# ------------------------------------------------------------------------------
# To use your 3080/4090, install Ollama on the host and set OLLAMA_HOST=0.0.0.0
# Then point this URL to http://<HOST_IP>:11434/api

# Provider Selection (openai, anthropic, ollama, etc)
DEFAULT_LLM_PROVIDER=ollama
# CHAT_LLM_PROVIDER=ollama 

# Ollama Configuration
# Use http://host.docker.internal:11434/api if Ollama is on the Proxmox Host (and see extra_hosts in compose)
# Use http://192.168.X.X:11434/api if Ollama is on Unraid/External
OLLAMA_BASE_URL=http://host.docker.internal:11434/api
NEXT_PUBLIC_OLLAMA_MODEL=llama3

# OpenAI (Optional fallback)
# OPENAI_API_KEY=sk-...
EOF

# ---------------------------------------------------------------------------------
# Save generated credentials
# ---------------------------------------------------------------------------------
cat <<EOF > ~/inbox-zero.creds
Inbox Zero Credentials
======================
Generated on: $(date)

PostgreSQL Password: ${POSTGRES_PASSWORD}
NextAuth Secret: ${NEXTAUTH_SECRET}
Email Encrypt Salt: ${EMAIL_ENCRYPT_SALT}

Database Connection:
  Host: localhost (inside container: db)
  Port: 5432
  Database: inboxzero
  User: postgres
  Password: ${POSTGRES_PASSWORD}

These credentials have been automatically set in /opt/inbox-zero/.env
Keep this file secure and delete after backing up elsewhere.
EOF

# ---------------------------------------------------------------------------------
# Generate README with setup instructions
# ---------------------------------------------------------------------------------
cat <<'EOF' > README.txt
INBOX ZERO SETUP INSTRUCTIONS
==============================

REQUIRED MANUAL STEPS:
1. Edit the configuration file:
   nano /opt/inbox-zero/.env

2. Add your GOOGLE_CLIENT_ID and SECRET (Required for login):
   - Go to: https://console.cloud.google.com/
   - Create a new project or select an existing one
   - Enable the Gmail API
   - Create OAuth 2.0 credentials
   - Add authorized redirect URI: http://<YOUR_CONTAINER_IP>:3000/api/auth/callback/google
   - Copy the Client ID and Client Secret to .env

3. (Optional) Configure Ollama/Local AI:
   - Verify the OLLAMA_BASE_URL matches your GPU server IP
   - Default assumes Ollama is running on the host via 11434
   - On your GPU host (Proxmox/Unraid), ensure Ollama is configured:
     * Install Ollama: https://ollama.ai/
     * Set OLLAMA_HOST=0.0.0.0 in the Ollama service configuration
     * Pull a model: ollama pull llama3
   - Update NEXT_PUBLIC_OLLAMA_MODEL to match your pulled model

4. Start the application:
   cd /opt/inbox-zero && docker compose up -d

5. Access the application:
   http://<YOUR_CONTAINER_IP>:3000

HEALTH MONITORING:
Health checks are configured for all services:
- Database: Validates PostgreSQL is ready
- Redis: Validates Redis is responding
- Web: Validates application is serving requests

To check service health:
  docker compose ps
  
To view detailed health status:
  docker inspect inbox-zero --format='{{.State.Health.Status}}'
  docker inspect inbox-zero-db --format='{{.State.Health.Status}}'
  docker inspect inbox-zero-redis --format='{{.State.Health.Status}}'

UPDATING:
To update Inbox Zero to the latest version:
  cd /opt/inbox-zero
  docker compose pull
  docker compose up -d --remove-orphans

LOGS:
To view logs:
  docker compose logs -f web
  
To troubleshoot database issues:
  docker compose logs db
EOF

msg_ok "Installed Inbox Zero Configuration"

# ---------------------------------------------------------------------------------
# Post-Install Instructions & Checks
# ---------------------------------------------------------------------------------
echo ""
echo -e "${INFO}${YW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
echo -e "${INFO}${YW} IMPORTANT: Credentials saved to ~/inbox-zero.creds${CL}"
echo -e "${INFO}${YW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
echo -e "${INFO}${YW} REQUIRED MANUAL STEPS:${CL}"
echo -e "${INFO}${YW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
echo -e "${INFO}${YW} 1. Edit the configuration file:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}nano /opt/inbox-zero/.env${CL}"
echo -e "${INFO}${YW} 2. Add your GOOGLE_CLIENT_ID and SECRET (Required for login).${CL}"
echo -e "${INFO}${YW} 3. Verify the OLLAMA_BASE_URL matches your GPU server IP.${CL}"
echo -e "${INFO}${YW}    (Default assumes Ollama is running on the host via 11434)${CL}"
echo -e "${INFO}${YW} 4. Start the application:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}cd /opt/inbox-zero && docker compose up -d${CL}"
echo -e "${INFO}${YW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
echo -e "${INFO}${YW} Full instructions: /opt/inbox-zero/README.txt${CL}"
echo -e "${INFO}${YW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
echo ""

# Ask user if they want to attempt start now
read -r -p "${TAB3}Would you like to start the containers now? (Will fail login if keys aren't set) <y/N> " prompt
echo
if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
    cd /opt/inbox-zero || exit
    msg_info "Starting containers (this may take a moment)..."
    $STD docker compose up -d
    
    # Database connection validation
    msg_info "Validating database connection..."
    MAX_RETRIES=30
    RETRY_COUNT=0
    DB_READY=false
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if docker exec inbox-zero-db pg_isready -U postgres -d inboxzero >/dev/null 2>&1; then
            DB_READY=true
            break
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        sleep 2
    done
    
    if [ "$DB_READY" = true ]; then
        msg_ok "Database connection validated"
        
        # Check container health status
        msg_info "Checking service health..."
        sleep 5  # Give services time to start
        
        WEB_STATUS=$(docker inspect --format='{{.State.Health.Status}}' inbox-zero 2>/dev/null || echo "no_health")
        DB_STATUS=$(docker inspect --format='{{.State.Health.Status}}' inbox-zero-db 2>/dev/null || echo "no_health")
        REDIS_STATUS=$(docker inspect --format='{{.State.Health.Status}}' inbox-zero-redis 2>/dev/null || echo "no_health")
        
        echo ""
        echo -e "${INFO}${YW} Container Status:${CL}"
        echo -e "${TAB}• Database: ${GN}${DB_STATUS}${CL}"
        echo -e "${TAB}• Redis: ${GN}${REDIS_STATUS}${CL}"
        echo -e "${TAB}• Web: ${GN}${WEB_STATUS}${CL}"
        echo ""
        
        if [[ "$WEB_STATUS" == "starting" ]] || [[ "$WEB_STATUS" == "no_health" ]]; then
            echo -e "${INFO}${YW} Note: Web service is starting. Health checks may take 30-60 seconds.${CL}"
            echo -e "${INFO}${YW} Check status with: ${BGN}docker compose ps${CL}"
        fi
        
        msg_ok "Started Inbox Zero"
    else
        msg_error "Database failed to become ready after $MAX_RETRIES attempts"
        echo -e "${INFO}${RD} Check logs with: cd /opt/inbox-zero && docker compose logs db${CL}"
        exit 1
    fi
else
    msg_info "Skipping start. Remember to configure .env first!"
fi

motd_ssh
customize
cleanup_lxc
