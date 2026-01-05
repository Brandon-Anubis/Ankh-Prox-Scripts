#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: Brandon-Anubis (Adapted)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/elie222/inbox-zero

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
  curl -fsSL https://api.github.com/repos/$1/releases/latest | grep '"tag_name":' | cut -d'"' -f4
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
mkdir -p $DOCKER_CONFIG/cli-plugins
curl -fsSL https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_LATEST_VERSION/docker-compose-linux-x86_64 -o ~/.docker/cli-plugins/docker-compose
chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
msg_ok "Installed Docker Compose $DOCKER_COMPOSE_LATEST_VERSION"

msg_info "Installing Inbox Zero"
mkdir -p /opt/inbox-zero
cd /opt/inbox-zero || exit

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
      - db
      - redis
    restart: always
    # Map extra hosts if you need to reach the host via host.docker.internal
    extra_hosts:
      - "host.docker.internal:host-gateway"

  db:
    image: postgres:15-alpine
    container_name: inbox-zero-db
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: inboxzero
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: always

  redis:
    image: redis:alpine
    container_name: inbox-zero-redis
    restart: always

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
NEXTAUTH_SECRET=$(openssl rand -base64 32)
EMAIL_ENCRYPT_SALT=$(openssl rand -hex 16)

# Database & Redis (Internal Docker Network)
DATABASE_URL=postgresql://postgres:password@db:5432/inboxzero
DIRECT_URL=postgresql://postgres:password@db:5432/inboxzero
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

UPDATING:
To update Inbox Zero to the latest version:
  cd /opt/inbox-zero
  docker compose pull
  docker compose up -d --remove-orphans

LOGS:
To view logs:
  docker compose logs -f web
EOF

msg_ok "Installed Inbox Zero Configuration"

# ---------------------------------------------------------------------------------
# Post-Install Instructions & Checks
# ---------------------------------------------------------------------------------
echo ""
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
read -r -p "Would you like to start the containers now? (Will fail login if keys aren't set) [y/N] " prompt
echo
if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
    cd /opt/inbox-zero || exit
    $STD docker compose up -d
    msg_ok "Started Inbox Zero"
else
    msg_info "Skipping start. Remember to configure .env first!"
fi

motd_ssh
customize
cleanup_lxc
