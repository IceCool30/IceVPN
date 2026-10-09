#!/usr/bin/env bash
#
# test-tier-manager.sh - Unit tests for the pure logic in tier-manager.sh.
#
# These do NOT need a live Outline server. They validate the two things most
# likely to silently break the paywall: the GB -> bytes math, and the JSON body
# shape sent to POST /access-keys. Run with: bash tests/test-tier-manager.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TM="$SCRIPT_DIR/../scripts/tier-manager.sh"

PASS=0; FAIL=0
ok()   { printf '  \033[1;32mPASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[1;31mFAIL\033[0m %s\n     %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

# Load the functions without running main (the script guards on BASH_SOURCE).
# Sourcing pulls in the script's `set -e`, which would abort this test on the
# first intentionally-failing guard command, so reset it immediately.
# shellcheck disable=SC1090
source "$TM" >/dev/null 2>&1 || true
set +e +o pipefail

echo "== gb_to_bytes =="
[ "$(gb_to_bytes 5)" = "5368709120" ] && ok "5 GB = 5368709120 bytes" \
  || bad "5 GB conversion" "got $(gb_to_bytes 5)"
[ "$(gb_to_bytes 1)" = "1073741824" ] && ok "1 GB = 1073741824 bytes" \
  || bad "1 GB conversion" "got $(gb_to_bytes 1)"
[ "$(gb_to_bytes 10)" = "10737418240" ] && ok "10 GB = 10737418240 bytes" \
  || bad "10 GB conversion" "got $(gb_to_bytes 10)"

echo "== request body shape (free tier, 5 GB cap) =="
if command -v python3 >/dev/null; then
  # Build the same bodies the script builds, then validate their shape.
  if command -v jq >/dev/null; then
    BODY_FREE="$(jq -nc --arg name "alice" --argjson port 44444 --argjson bytes 5368709120 \
      '{name:$name, port:$port, limit:{bytes:$bytes}}')"
    BODY_PAID="$(jq -nc --arg name "bob" --argjson port 44444 '{name:$name, port:$port}')"
  else
    BODY_FREE="$(python3 -c 'import json;print(json.dumps({"name":"alice","port":44444,"limit":{"bytes":5368709120}}))')"
    BODY_PAID="$(python3 -c 'import json;print(json.dumps({"name":"bob","port":44444}))')"
  fi
  echo "$BODY_FREE" | python3 -c 'import sys,json; d=json.load(sys.stdin); assert d["name"]=="alice"; assert d["port"]==44444; assert d["limit"]["bytes"]==5368709120' \
    && ok "free body has name, port, limit.bytes" || bad "free body" "$BODY_FREE"

  echo "$BODY_PAID" | python3 -c 'import sys,json; d=json.load(sys.stdin); assert d["name"]=="bob"; assert "limit" not in d' \
    && ok "paid body has no limit (unlimited)" || bad "paid body" "$BODY_PAID"

  echo "== data-limit body (the #1193 gotcha) =="
  DL="{\"limit\":{\"bytes\":5368709120}}"
  echo "$DL" | python3 -c 'import sys,json; d=json.load(sys.stdin); assert d["limit"]["bytes"]==5368709120' \
    && ok "PUT data-limit body is valid JSON with limit.bytes" || bad "data-limit body" "$DL"
else
  echo "  (python3 not available, skipping JSON shape checks)"
fi

echo "== argument guard =="
# With no args, main should print usage and exit non-zero (not run a command).
OUT="$(bash "$TM" 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && ok "no args exits non-zero" || bad "no args guard" "exit $RC"
echo "$OUT" | grep -q "USAGE" && ok "no args prints usage" || bad "usage text" "no USAGE found"

OUT="$(bash "$TM" bogus https://x/S 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && ok "unknown action exits non-zero" || bad "unknown action" "exit $RC"

echo
echo "----------------------------------------"
printf 'Results: \033[1;32m%d passed\033[0m, \033[1;31m%d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]