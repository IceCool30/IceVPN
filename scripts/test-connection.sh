#!/usr/bin/env bash
#
# test-connection.sh - Verify your IceVPN actually works and does not leak.
# Runs on Linux/macOS. On Windows use Git Bash or WSL.
#
# It checks: (1) your real public IP before, (2) that the management API
# answers, and (3) prints where to check for DNS leaks after you connect.

set -uo pipefail

API_URL="${1:-}"
log()  { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn] %s\033[0m\n' "$*"; }

log "Your current public IP (this should change once the VPN is on):"
curl -sS https://ipinfo.io/json 2>/dev/null \
  | jq -r '"\(.ip)  \(.city), \(.country)  (\(.org))"' 2>/dev/null \
  || warn "Could not reach ipinfo.io (offline?)"

if [ -n "$API_URL" ]; then
  log "Pinging the IceVPN management API:"
  code="$(curl -sS --insecure -o /dev/null -w '%{http_code}' "${API_URL}/server" 2>/dev/null || echo 000)"
  if [ "$code" = "200" ]; then
    echo "  OK (HTTP 200). Server reachable."
    curl -sS --insecure "${API_URL}/server" 2>/dev/null | jq '{name,version,metricsEnabled}'
  else
    warn "API returned HTTP ${code}. Check the cloud firewall (Layer 2) and that the URL is exact."
  fi
fi

cat <<EOF

Manual checks after you connect a client:
  1. Reload https://ipinfo.io  -> IP must now be your VPS IP, not your real one.
  2. Go to https://dnsleaktest.com -> Extended test -> confirm your ISP name is
     gone and you see the VPS provider instead.
  3. https://browserleaks.com/webrtc -> make sure your real IP is not exposed.

If it connects but pages do not load, it is almost always the CLOUD firewall
(Layer 2). If it will not connect at all, check the IP and port in the ss:// link
match what you opened.

EOF