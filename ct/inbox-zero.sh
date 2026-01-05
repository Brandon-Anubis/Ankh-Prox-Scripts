#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/Brandon-Anubis/Ankh-Prox-Scripts/main/misc/build.func)
# Copyright (c) 2021-2025 tteck
# Author: Brandon-Anubis (Adapted)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/elie222/inbox-zero

APP="Inbox Zero"
var_tags="${var_tags:-email;ai;productivity}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/inbox-zero ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP}"
  cd /opt/inbox-zero || exit
  $STD docker compose pull
  $STD docker compose up -d --remove-orphans
  msg_ok "Updated ${APP}"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
echo -e "${INFO}${YW} IMPORTANT: You must configure /opt/inbox-zero/.env before the app will work.${CL}"
echo -e "${INFO}${YW} See /opt/inbox-zero/README.txt for setup instructions.${CL}"
