#!/usr/bin/env bash
# Per-user Signals through rz_run (P3-C2, DECISIONS A9, A10, F5): the first GET and the
# socket see the same guard user; joins are per-user, guarded, and bound to the page
# path the socket was opened for.
#   ./tests/fixtures/app/live/test.sh [binary] [port] [rzpp]
# Run from the repository root.
set -u
BIN=${1:-build/live}
PORT=${2:-8072}
[ -n "$PORT" ] || PORT=8072
DIR=$(dirname "$0")
LOG=$(mktemp)
PID=""
PASS=0
FAIL=0
B=http://127.0.0.1:$PORT

cleanup() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; fi
  rm -f "$LOG"
}
trap cleanup EXIT

ok()  { echo "PASS  $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL  $1: $2"; FAIL=$((FAIL + 1)); }
# want <label> <status> <body-substring> <curl args...>
want() {
  local label=$1 status=$2 sub=$3; shift 3
  local out code body
  out=$(curl -s -w '\n%{http_code}' "$@")
  code=${out##*$'\n'}; body=${out%$'\n'*}
  if [ "$code" = "$status" ] && [[ "$body" == *"$sub"* ]]; then ok "$label -> $code"
  else bad "$label" "want $status ~$sub, got $code ${body:0:300}"; fi
}

"$BIN" --port "$PORT" >"$LOG" 2>&1 &
PID=$!
for _ in $(seq 1 50); do grep -q listening "$LOG" && break; sleep 0.1; done
grep -q "live: listening on 127.0.0.1:$PORT" "$LOG" && ok "listening line" || { bad "listening line" "$(cat "$LOG")"; exit 1; }

LOC=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "$B/admin")
[ "$LOC" = "302 $B/login" ] && ok "GET /admin without a cookie -> 302 /login" || bad "GET /admin no cookie" "got $LOC"
want "GET /admin as ann shows ann (2-arg mount, same user as the socket)" 200 '<p class="who">ann</p><p class="sid">ann-token</p><p class="path">&#x2F;admin</p><p class="n">10</p>' -H 'Cookie: sid=ann-token' "$B/admin"
want "GET /admin as bob shows bob" 200 '<p class="who">bob</p><p class="sid">bob-token</p><p class="path">&#x2F;admin</p><p class="n">20</p>' -H 'Cookie: sid=bob-token' "$B/admin"
want "GET /admin as eve: the mount refuses (RZ_E_NOT_FOUND -> 404)" 404 'not found' -H 'Cookie: sid=eve-token' "$B/admin"
want "GET /public (1-arg mount, no guard)" 200 '<p class="hits">5</p>' "$B/public"
want "signal.js sends the page path" 200 '&path=" + encodeURIComponent(location.pathname)' "$B/rz/signal.js"

if python3 "$DIR/client.py" "$PORT"; then ok "live client"; else bad "live client" "see above"; fi
kill -0 "$PID" 2>/dev/null && ok "server still up" || bad "server" "exited: $(cat "$LOG")"

echo
if [ "$FAIL" -eq 0 ]; then echo "LIVE APP OK ($PASS checks)"; exit 0; fi
echo "LIVE APP FAILED ($FAIL of $((PASS + FAIL)))"; exit 1
