#!/usr/bin/env bash
#
# bootstrap.sh - Turn a fresh Ubuntu VPS into a hardened IceVPN (Outline) server.
#
# WHAT IT DOES
#   1. Updates the system, installs Docker prerequisites, fail2ban, and
#      unattended security upgrades.
#   2. Runs the OFFICIAL Outline (Shadowbox) installer with PINNED ports, so the
#      firewall is deterministic. It prints an access JSON (apiUrl + certSha256)
#      you paste into the Outline Manager app.
#   3. Locks the OS firewall down to fail-closed: only SSH, the management port,
#      and the single pinned access-key port stay open. Everything else drops.
#
# WHY PINNED PORTS
#   Outline's own installer warns that if access keys use more than one port, the
#   firewall guidance is wrong. By default new keys can land on random ports.
#   We pass --api-port and --keys-port so ALL keys share ONE known port. Result:
#   a clean, minimal 2-port + SSH firewall you can open once and forget.
#
# HOW TO RUN
#   ssh into your fresh VPS, then:
#       sudo bash bootstrap.sh
#   Keep this SSH session open and watch for the green "apiUrl" JSON at the end.
#
# BEFORE YOU RUN
#   Open these ports in your provider's CLOUD firewall too (two separate layers).
#   Oracle Cloud uses TWO layers (Security List + NSG). See oci-firewall-guide.md.
#   Defaults below: SSH 22 (TCP), management 25565 (TCP), keys 44444 (TCP+UDP).

set -euo pipefail

# ----- Config you can edit -----
SSH_PORT="${SSH_PORT:-22}"
MGMT_PORT="${MGMT_PORT:-25565}"     # Outline management API (TCP only)
KEYS_PORT="${KEYS_PORT:-44444}"     # Shadowsocks access keys (TCP + UDP)

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[error] %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root: sudo bash bootstrap.sh"

if [ "$MGMT_PORT" = "$KEYS_PORT" ]; then
  die "MGMT_PORT and KEYS_PORT must differ (Outline rejects equal ports)."
fi

log "1/5 Updating system and installing base tools"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl jq ufw ca-certificates gnupg

log "2/5 Installing Docker (required by Outline)"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
else
  echo "  Docker already present."
fi

log "3/5 Enabling automatic security updates and fail2ban"
apt-get install -y fail2ban unattended-upgrades
systemctl enable --now unattended-upgrades || true
systemctl enable --now fail2ban || true

log "4/5 Installing Outline Server (official installer, pinned ports)"
# --api-port  : the management API port (TCP)
# --keys-port : the single port every access key will use (TCP + UDP)
bash -c "$(curl -sS https://raw.githubusercontent.com/Jigsaw-Code/outline-server/master/src/server_manager/install_scripts/install_server.sh)" \
  -- --api-port "${MGMT_PORT}" --keys-port "${KEYS_PORT}" \
  || die "Outline installer failed. Scroll up for the reason."

log "5/5 Locking down the OS firewall (fail-closed)"
IFACE="$(ip route show default | awk '{print $5; exit}')"
[ -n "$IFACE" ] || die "Could not detect default network interface."

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}/tcp"                  comment 'SSH'
ufw allow "${MGMT_PORT}/tcp"                 comment 'IceVPN management API (TCP)'
ufw allow "${KEYS_PORT}/tcp"                 comment 'IceVPN access keys (TCP)'
ufw allow "${KEYS_PORT}/udp"                 comment 'IceVPN access keys (UDP)'
ufw --force enable

log "Listening services (verify these match the ports you opened in the cloud firewall)"
ss -tulpn | grep -E 'docker|shadowbox|ss-server|:25565|:44444' || true

cat <<EOF

$(printf '\033[1;32m')
============================================================
 IceVPN (Outline) is installed.
============================================================$(printf '\033[0m')

NEXT STEP:
  1. Scroll UP and copy the green JSON line that starts with {"apiUrl":...
     It looks like:
       {"apiUrl":"https://YOUR_IP:${MGMT_PORT}/S3cr3tPath","certSha256":"...."}
  2. Open the Outline Manager app (Windows/Mac/Linux) or web manager, paste that
     JSON in, and connect.
  3. Create access keys from the Manager, or from the command line with
     ../scripts/tier-manager.sh (free cap vs paid unlimited).

PORTS TO OPEN IN YOUR CLOUD FIREWALL (Layer 2, in addition to this OS firewall):
  - ${SSH_PORT}/tcp   SSH
  - ${MGMT_PORT}/tcp  Management API
  - ${KEYS_PORT}/tcp  Access keys
  - ${KEYS_PORT}/udp  Access keys

REMINDER:
  - Ports must be open in your cloud provider firewall too, not just here.
    Oracle Cloud uses TWO layers. See ../config/oci-firewall-guide.md.
  - Test from a device on cellular data, not your own network, to confirm it
    really works end to end. The apiUrl is a secret. Treat it like a root password.

EOF