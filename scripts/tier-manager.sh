#!/usr/bin/env bash
#
# tier-manager.sh - Drive the Outline management API to run a free + paid tier.
#
# This is the script behind your paywall. It creates access keys and enforces a
# data cap on the free tier by calling the Outline API directly, so you can wire
# it into any payment flow (crypto, Stripe, whatever) later.
#
# VERIFIED AGAINST the official api.yml:
#   - GET    /access-keys                 list keys
#   - POST   /access-keys                 create a key (accepts name, port, limit)
#   - PUT    /access-keys/:id/data-limit  set a per-key cap, body {"limit":{"bytes":N}}
#   - DELETE /access-keys/:id/data-limit  remove the cap (unlimited / paid tier)
#   - DELETE /access-keys/:id             delete a key (revoke a user)
#   - GET    /metrics/transfer            bytes used per key
#
# NOTE ON TLS: The API uses a self-signed cert. We pass --insecure by default
# because the secret in the apiUrl path IS the authentication. To harden this,
# pin the cert with --cacert instead of disabling verification blindly.
#
# USAGE
#   ./tier-manager.sh list   <apiUrl>
#   ./tier-manager.sh usage  <apiUrl>
#   ./tier-manager.sh free   <apiUrl> <label> [port]    # FREE_TIER_GB cap (default 5)
#   ./tier-manager.sh paid   <apiUrl> <label> [port]    # unlimited
#   ./tier-manager.sh cap    <apiUrl> <id> <GB>         # set custom cap
#   ./tier-manager.sh uncap  <apiUrl> <id>              # lift cap (upgrade to paid)
#   ./tier-manager.sh delete <apiUrl> <id>              # revoke a user
#
# <apiUrl> is the green JSON line from the install, e.g.
#   https://1.2.3.4:25565/S3cr3tPath
#
# CONFIG (env vars)
#   FREE_TIER_GB=5   data cap for the free tier
#   KEYS_PORT=44444  the pinned Shadowsocks port from bootstrap.sh

set -euo pipefail

FREE_TIER_GB="${FREE_TIER_GB:-5}"
KEYS_PORT="${KEYS_PORT:-44444}"

log()  { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[error] %s\033[0m\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "Missing dependency: $1 (apt install $1)"; }

gb_to_bytes() { echo $(( $1 * 1024 * 1024 * 1024 )); }

# api <METHOD> <path> [json-body]
api() {
  local method="$1" path="$2" body="${3:-}"
  if [ -n "$body" ]; then
    curl -sS --insecure -X "$method" \
      -H 'Content-Type: application/json' \
      -d "$body" "${API_URL}${path}"
  else
    curl -sS --insecure -X "$method" "${API_URL}${path}"
  fi
}

cmd_list() {
  log "Access keys"
  api GET /access-keys | jq -r '.accessKeys[] | "\(.id)\t\(.name // "-")\tport=\(.port)"'
}

cmd_usage() {
  log "Data transferred per key (bytes)"
  api GET /metrics/transfer | jq '.bytesTransferredByUserId'
}

# create_key <label> <cap_gb> <port>
# Creates a key with the name, the pinned port, and (optionally) a byte limit,
# all in ONE POST request as the official API allows.
create_key() {
  local label="$1" cap_gb="$2" port="$3"
  local body
  if [ "$cap_gb" = "0" ]; then
    body="$(jq -nc --arg name "$label" --argjson port "$port" \
      '{name:$name, port:$port}')"
  else
    body="$(jq -nc --arg name "$label" --argjson port "$port" --argjson bytes "$(gb_to_bytes "$cap_gb")" \
      '{name:$name, port:$port, limit:{bytes:$bytes}}')"
  fi

  log "Creating key: $label (port ${port}, cap $([ "$cap_gb" = "0" ] && echo unlimited || echo "${cap_gb}GB"))"
  local resp
  resp="$(api POST /access-keys "$body")"
  local id access_url
  id="$(echo "$resp" | jq -r '.id')"
  access_url="$(echo "$resp" | jq -r '.accessUrl')"
  [ -n "$id" ] && [ "$id" != "null" ] || die "Create failed: $resp"

  cat <<EOF

  Created access key id=${id}
  Hand this ss:// link to the user's Outline client app (Android/iPhone/Win/Mac):
    ${access_url}

EOF
}

cmd_free() { create_key "${2:-free-user}" "$FREE_TIER_GB" "${3:-$KEYS_PORT}"; }
cmd_paid() { create_key "${2:-paid-user}" "0" "${3:-$KEYS_PORT}"; }

cmd_cap() {
  local id="$1" gb="$2" bytes code
  bytes="$(gb_to_bytes "$gb")"
  log "Setting cap on key ${id} to ${gb} GB (${bytes} bytes)"
  # Content-Type header is REQUIRED or the API rejects the body (see issue #1193).
  code="$(curl -sS --insecure -o /dev/null -w '%{http_code}' \
    -X PUT -H 'Content-Type: application/json' \
    -d "{\"limit\":{\"bytes\":${bytes}}}" \
    "${API_URL}/access-keys/${id}/data-limit")"
  [ "$code" = "204" ] || die "Cap failed (HTTP ${code}). If it silently ignores, set it in the Manager GUI."
  echo "  OK"
}

cmd_uncap() {
  log "Lifting cap on key $1 (paid upgrade)"
  local code
  code="$(curl -sS --insecure -o /dev/null -w '%{http_code}' \
    -X DELETE "${API_URL}/access-keys/$1/data-limit")"
  [ "$code" = "204" ] || die "Uncap failed (HTTP ${code})"
  echo "  OK, key $1 is now unlimited"
}

cmd_delete() {
  log "Revoking key $1"
  local code
  code="$(curl -sS --insecure -o /dev/null -w '%{http_code}' \
    -X DELETE "${API_URL}/access-keys/$1")"
  [ "$code" = "204" ] || die "Delete failed (HTTP ${code})"
  echo "  OK, key $1 revoked"
}

main() {
  local action="${1:-}"; API_URL="${2:-}"
  [ -n "$action" ] && [ -n "$API_URL" ] || { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
  # Dependency checks run here, at real invocation, so tests can source the
  # pure functions without curl/jq installed.
  need curl
  need jq
  case "$action" in
    list)   cmd_list ;;
    usage)  cmd_usage ;;
    free)   cmd_free "$@" ;;
    paid)   cmd_paid "$@" ;;
    cap)    cmd_cap "${3:-}" "${4:-}" ;;
    uncap)  cmd_uncap "${3:-}" ;;
    delete) cmd_delete "${3:-}" ;;
    *)      die "Unknown action: $action (try list, usage, free, paid, cap, uncap, delete)" ;;
  esac
}
# Only run main when executed directly, so tests can source the functions.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi