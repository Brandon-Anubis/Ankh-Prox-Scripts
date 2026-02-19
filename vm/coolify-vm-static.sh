#!/usr/bin/env bash
# =============================================================================
# coolify-vm-static.sh — Static IP overlay for coolify-vm.sh
# =============================================================================
# Sets a static IP before calling the main VM creation script.
# Usage:
#   export COOLIFY_IP="192.168.5.220"
#   export COOLIFY_GW="192.168.5.1"
#   export COOLIFY_MASK="24"
#   bash vm/coolify-vm-static.sh
#
# All other env vars from coolify-vm.sh are respected:
#   SSH_KEY, STORAGE, BRIDGE, VMID
# =============================================================================

set -euo pipefail

COOLIFY_IP="${COOLIFY_IP:-}"
COOLIFY_GW="${COOLIFY_GW:-}"
COOLIFY_MASK="${COOLIFY_MASK:-24}"

if [[ -z "${COOLIFY_IP}" || -z "${COOLIFY_GW}" ]]; then
  echo "[ERROR] COOLIFY_IP and COOLIFY_GW must be set."
  echo "  Example: COOLIFY_IP=192.168.5.220 COOLIFY_GW=192.168.5.1 bash vm/coolify-vm-static.sh"
  exit 1
fi

# Validate IP format
if ! [[ "${COOLIFY_IP}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "[ERROR] COOLIFY_IP '${COOLIFY_IP}' is not a valid IPv4 address."
  exit 1
fi

echo "[INFO] Will configure static IP: ${COOLIFY_IP}/${COOLIFY_MASK} via ${COOLIFY_GW}"

# Monkey-patch the ipconfig0 line after VM creation by hooking into
# the post-build phase. We override the qm set --ipconfig0 call by
# exporting STATIC_IP_CONFIG so the main script picks it up.
export STATIC_IP_CONFIG="ip=${COOLIFY_IP}/${COOLIFY_MASK},gw=${COOLIFY_GW}"

# Source and run the main script, with STATIC_IP_CONFIG in env
# The main script checks for this variable and substitutes dhcp.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${SCRIPT_DIR}/coolify-vm.sh"
