#!/usr/bin/env bash

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
# Copyright (c) 2021-2025 community-scripts ORG
# Author: [YourGitHubUsername]
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://coolify.io

# Fallback if FUNCTIONS_FILE_PATH is not set or empty
if [ -z "$FUNCTIONS_FILE_PATH" ]; then
  export BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/Brandon-Anubis/Ankh-Prox-Scripts/main}"
  FUNCTIONS_FILE_PATH="$(curl -fsSL "${BASE_URL}"/misc/install.func)"
fi

# App Default Values
APP="Coolify"
var_tags="${var_tags:-selfhosted;paas}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-200}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_unprivileged="${var_unprivileged:-0}"  # VM — not applicable; set 0 for privileged-equivalent

# =============================================================================
# VM-SPECIFIC CONFIGURATION
# =============================================================================
# This script provisions a QEMU/KVM VM (not an LXC container) because Coolify
# manages Docker and requires direct kernel access unavailable in unprivileged LXC.
#
# STORAGE: default "local-lvm". Override: STORAGE="zfs-pool" bash vm/coolify-vm.sh
# BRIDGE:  default "vmbr0".    Override: BRIDGE="vmbr1" bash vm/coolify-vm.sh
# VMID:    auto-selected by build.func. Override: VMID=200 bash vm/coolify-vm.sh
#
# Cloud image is downloaded once to /var/lib/vz/template/iso/ and reused.
# =============================================================================

CLOUD_IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
CLOUD_IMAGE_FILE="/var/lib/vz/template/iso/noble-server-cloudimg-amd64.img"
STORAGE="${STORAGE:-local-lvm}"
BRIDGE="${BRIDGE:-vmbr0}"

header_info "$APP"
variables
color
catch_errors

# =============================================================================
# UPDATE FUNCTION — SSHes into the VM to upgrade Coolify
# =============================================================================

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  # Resolve the VM's IP from its cloud-init config
  VMID="${VMID:-$(qm list | grep -i coolify | awk '{print $1}' | head -1)}"
  if [[ -z "${VMID}" ]]; then
    msg_error "No Coolify VM found. Cannot update."
    exit 1
  fi

  VM_IP=$(qm cloudinit dump "${VMID}" user 2>/dev/null | grep -oP 'ip=\K[^/]+' | head -1)
  if [[ -z "${VM_IP}" ]]; then
    VM_IP=$(qm guest cmd "${VMID}" network-get-interfaces 2>/dev/null | \
      python3 -c "import json,sys; ifaces=json.load(sys.stdin); \
        [print(a['ip-address']) for i in ifaces for a in i.get('ip-addresses',[]) \
        if a['ip-address-type']=='ipv4' and not a['ip-address'].startswith('127')]" 2>/dev/null | head -1)
  fi

  if [[ -z "${VM_IP}" ]]; then
    msg_error "Cannot determine VM IP. Update manually: ssh root@<VM_IP> 'curl -fsSL https://cdn.coollabs.io/coolify/upgrade.sh | bash'"
    exit 1
  fi

  msg_info "Updating ${APP} on VM (${VM_IP})"
  CURRENT=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@${VM_IP}" \
    "docker inspect coolify --format '{{.Config.Image}}' 2>/dev/null | grep -oP 'v[\d.]+'" 2>/dev/null || echo "unknown")
  msg_info "Current version: ${CURRENT}"

  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@${VM_IP}" \
    "curl -fsSL https://cdn.coollabs.io/coolify/upgrade.sh | bash" || {
    msg_error "Update failed. Check connectivity to ${VM_IP}."
    exit 1
  }
  msg_ok "Updated ${APP} successfully"
  exit
}

# =============================================================================
# HELPER: Download cloud image (idempotent)
# =============================================================================

function download_cloud_image() {
  if [[ -f "${CLOUD_IMAGE_FILE}" ]]; then
    msg_ok "Cloud image already present: ${CLOUD_IMAGE_FILE}"
    return
  fi
  msg_info "Downloading Ubuntu 24.04 cloud image (~700 MB)"
  if ! wget -q --show-progress -O "${CLOUD_IMAGE_FILE}" "${CLOUD_IMAGE_URL}"; then
    rm -f "${CLOUD_IMAGE_FILE}"
    msg_error "Failed to download cloud image from ${CLOUD_IMAGE_URL}"
    exit 1
  fi
  msg_ok "Downloaded Ubuntu 24.04 cloud image"
}

# =============================================================================
# HELPER: Collect SSH public key interactively
# =============================================================================

function collect_ssh_key() {
  if [[ -n "${SSH_KEY:-}" ]]; then
    msg_ok "Using provided SSH_KEY environment variable"
    return
  fi

  # Try to find a local public key first
  for keyfile in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub; do
    if [[ -f "${keyfile}" ]]; then
      SSH_KEY=$(cat "${keyfile}")
      msg_ok "Auto-detected SSH key: ${keyfile}"
      return
    fi
  done

  # Prompt interactively
  if [[ -t 0 ]]; then
    echo ""
    msg_info "No SSH public key found. Paste your public key below (required for VM access):"
    read -r SSH_KEY
    if [[ -z "${SSH_KEY}" ]]; then
      msg_error "SSH public key is required. Set SSH_KEY env var or paste during prompt."
      exit 1
    fi
    msg_ok "SSH key accepted"
  else
    msg_error "No SSH_KEY set and running non-interactively. Export SSH_KEY before running."
    exit 1
  fi
}

# =============================================================================
# HELPER: Generate cloud-init user-data
# =============================================================================

function generate_cloud_init() {
  local vmid="$1"
  local snippet_path="/var/lib/vz/snippets/coolify-${vmid}-userdata.yaml"

  # Ensure snippets directory exists (must be enabled in Proxmox storage config)
  mkdir -p /var/lib/vz/snippets

  cat > "${snippet_path}" <<CLOUDINIT
#cloud-config
hostname: coolify
fqdn: coolify.local
timezone: UTC
package_update: true
package_upgrade: true
packages:
  - curl
  - ca-certificates
  - ufw

users:
  - name: root
    ssh_authorized_keys:
      - "${SSH_KEY}"

write_files:
  - path: /etc/ssh/sshd_config.d/99-harden.conf
    content: |
      PermitRootLogin prohibit-password
      PasswordAuthentication no
      PubkeyAuthentication yes

runcmd:
  # Harden firewall — Coolify ports locked down by default
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow 22/tcp comment 'SSH'
  - ufw allow 80/tcp comment 'HTTP (Coolify Traefik)'
  - ufw allow 443/tcp comment 'HTTPS (Coolify Traefik)'
  - ufw allow 8000/tcp comment 'Coolify Dashboard'
  - ufw --force enable

  # Install Coolify (official install script)
  - curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash

  - systemctl restart ssh

final_message: "Coolify VM is ready. Access the dashboard at http://\$INSTANCE_IP:8000"
CLOUDINIT

  echo "${snippet_path}"
}

# =============================================================================
# HELPER: Build the VM
# =============================================================================

function build_vm() {
  local vmid="$1"

  download_cloud_image
  collect_ssh_key

  local snippet_path
  snippet_path=$(generate_cloud_init "${vmid}")
  msg_ok "Generated cloud-init user-data: ${snippet_path}"

  msg_info "Creating VM ${vmid} (${APP})"
  qm create "${vmid}" \
    --name "coolify" \
    --cores "${var_cpu}" \
    --memory "${var_ram}" \
    --net0 "virtio,bridge=${BRIDGE}" \
    --ostype l26 \
    --machine q35 \
    --bios ovmf \
    --efidisk0 "${STORAGE}:0,efitype=4m,pre-enrolled-keys=0" \
    --agent enabled=1 \
    --onboot 1 \
    --tags "${var_tags//;/,}" \
    2>&1 | grep -v "^$" || { msg_error "qm create failed"; exit 1; }
  msg_ok "Created VM skeleton"

  msg_info "Importing disk image into ${STORAGE}"
  qm importdisk "${vmid}" "${CLOUD_IMAGE_FILE}" "${STORAGE}" --format qcow2 \
    2>&1 | tail -1
  msg_ok "Imported disk"

  msg_info "Configuring VM hardware"
  qm set "${vmid}" \
    --scsihw virtio-scsi-pci \
    --scsi0 "${STORAGE}:vm-${vmid}-disk-1,discard=on,ssd=1" \
    --boot order=scsi0 \
    --ide2 "${STORAGE}:cloudinit" \
    --serial0 socket \
    --vga serial0 \
    --ipconfig0 "${STATIC_IP_CONFIG:-ip=dhcp}" \
    --cicustom "user=local:snippets/coolify-${vmid}-userdata.yaml"
  msg_ok "Configured VM hardware"

  msg_info "Resizing disk to ${var_disk}G"
  qm resize "${vmid}" scsi0 "${var_disk}G"
  msg_ok "Disk resized to ${var_disk}G"
}

# =============================================================================
# MAIN ENTRY POINT
# =============================================================================
# build.func's start() handles VMID selection, storage prompts, and the
# interactive/non-interactive mode toggle. We override build_container()
# with our VM-specific build_vm() since LXC functions don't apply here.

start

# Select next available VMID if not set
VMID="${VMID:-$(pvesh get /cluster/nextid 2>/dev/null || echo 200)}"

build_vm "${VMID}"

msg_info "Starting VM ${VMID}"
qm start "${VMID}"
msg_ok "VM ${VMID} started"

description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} VM has been provisioned!${CL}"
echo -e "${INFO}${YW} Cloud-init will run the Coolify installer on first boot (~3-5 min).${CL}"
echo -e "${INFO}${YW} Monitor boot progress:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}qm terminal ${VMID}${CL}"
echo -e "${INFO}${YW} Once booted, access Coolify at:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://<VM-IP>:8000${CL}"
echo -e "${INFO}${YW} Get VM IP:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}qm guest cmd ${VMID} network-get-interfaces${CL}"
echo -e ""
echo -e "${INFO}${YW} Static IP override (edit before running):${CL}"
echo -e "${TAB}${BGN}STORAGE=local-lvm BRIDGE=vmbr0 bash vm/coolify-vm.sh${CL}"
