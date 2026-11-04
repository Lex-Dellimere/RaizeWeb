#!/usr/bin/env bash
# The P2 draft slice (DECISIONS.md D7): resource JSON API, Signal, rz_run startup errors.
#   ./tests/fixtures/app/slice/test.sh [binary] [port] [rzpp]
# Run from the repository root.
set -u
BIN=${1:-build/slice}
PORT=${2:-8075}
RZPP=${3:-build/rzpp}
DIR=$(dirname "$0")
LOG=$(mktemp)
PID=""
PASS=0
FAIL=0

cleanup() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; fi
  rm -f "$LOG"
}
trap cleanup EXIT

ok()   { echo "PASS  $1"; PASS=$((PASS + 1)); }
bad()  { echo "FAIL  $1: $2"; FAIL=$((FAIL + 1)); }
# want <label> <status> <body-substring> <curl args...>
want() {
  local label=$1 status=$2 sub=$3; shift 3
  local out code body
  out=$(curl -s -w '\n%{http_code}' "$@")
  code=${out##*$'\n'}; body=${out%$'\n'*}
  if [ "$code" = "$status" ] && [[ "$body" == *"$sub"* ]]; then ok "$label -> $code ${body:0:70}"
  else bad "$label" "want $status ~$sub, got $code $body"; fi
}
# exact <label> <status> <whole-body> <curl args...>: the body must equal <whole-body>.
exact() {
  local label=$1 status=$2 whole=$3; shift 3
  local out code body
  out=$(curl -s -w '\n%{http_code}' "$@")
  code=${out##*$'\n'}; body=${out%$'\n'*}
  if [ "$code" = "$status" ] && [ "$body" = "$whole" ]; then ok "$label -> $code ${body:0:90}"
  else bad "$label" "want $status =$whole, got $code $body"; fi
}

"$BIN" --port "$PORT" >"$LOG" 2>&1 &
PID=$!
for _ in $(seq 1 50); do grep -q listening "$LOG" && break; sleep 0.1; done
grep -q "slice: listening on 127.0.0.1:$PORT" "$LOG" && ok "listening line" || bad "listening line" "$(cat "$LOG")"

API=http://127.0.0.1:$PORT/api/notes
J='-H Content-Type:application/json'
exact "POST valid"       201 '{"id":1,"text":"hello","pinned":false}' $J -X POST -d '{"text":"  hello  "}' "$API"
want "POST {}"           400 '"fields":{"text":"can'"'"'t be blank"}' $J -X POST -d '{}' "$API"
LONG=$(printf 'a%.0s' $(seq 1 41))
want "POST 41 bytes"     400 '"text":"is too long (at most 40)"' $J -X POST -d "{\"text\":\"$LONG\"}" "$API"
want "POST not object"   400 '"error":"body is not a JSON object"' $J -X POST -d '[1]' "$API"
exact "GET /1"           200 '{"id":1,"text":"hello","pinned":false}' "$API/1"
want "GET /999"          404 '"error":"not found"' "$API/999"
want "GET /abc"          400 '"error":"bad id"' "$API/abc"
want "POST /1/pin"       200 '"pinned":true' -X POST "$API/1/pin"
# The stored record, not the action's response copy: modify must write back.
exact "GET /1 after pin" 200 '{"id":1,"text":"hello","pinned":true}' "$API/1"
want "POST /999/pin"     404 'not found' -X POST "$API/999/pin"
exact "POST second"      201 '{"id":2,"text":"world","pinned":false}' $J -X POST -d '{"text":"world"}' "$API"
# scan: every stored record, in id order.
exact "GET list (2)"     200 '[{"id":1,"text":"hello","pinned":true},{"id":2,"text":"world","pinned":false}]' "$API"
want "DELETE /1"         204 '' -X DELETE "$API/1"
want "DELETE /1 again"   404 'not found' -X DELETE "$API/1"
exact "GET /1 deleted"   404 '{"error":"not found"}' "$API/1"
exact "GET list (1)"     200 '[{"id":2,"text":"world","pinned":false}]' "$API"
want "DELETE /2"         204 '' -X DELETE "$API/2"
exact "GET list (0)"     200 '[]' "$API"
want "GET /counter"      200 '<p>0</p>' "http://127.0.0.1:$PORT/counter"
want "GET /rz/signal.js" 200 '' "http://127.0.0.1:$PORT/rz/signal.js"

if python3 "$DIR/client.py" "$PORT"; then ok "signal client"; else bad "signal client" "see above"; fi
kill -0 "$PID" 2>/dev/null && ok "server still up" || bad "server" "exited: $(cat "$LOG")"

# Startup errors: exit 1 naming the variable; a taken port: exit 2.
MSG=$(RAIZE_PORT=x "$BIN" 2>&1); RC=$?
if [ $RC -eq 1 ] && [[ "$MSG" == *RAIZE_PORT* ]]; then ok "RAIZE_PORT=x -> exit 1: $MSG"; else bad "RAIZE_PORT=x" "rc=$RC [$MSG]"; fi
MSG=$("$BIN" --port "$PORT" 2>&1); RC=$?
if [ $RC -eq 2 ] && [[ "$MSG" == *"cannot listen on :$PORT"* ]]; then ok "port taken -> exit 2: $MSG"; else bad "port taken" "rc=$RC [$MSG]"; fi

# rzpp: a decorator naming an unknown field reports its line and the fields.
F=tests/fixtures/rzpp/bad_resource_field.mettle
MSG=$("$RZPP" "$F" "$LOG.gen" 2>&1); RC=$?
rm -f "$LOG.gen"
if [ $RC -ne 0 ] && [[ "$MSG" == "$F:3: "*"txt"*"id, text, pinned"* ]]; then ok "rzpp bad field: $MSG"; else bad "rzpp bad field" "rc=$RC [$MSG]"; fi

echo
if [ $FAIL -eq 0 ]; then echo "SLICE OK ($PASS checks)"; exit 0; fi
echo "SLICE FAILED ($FAIL of $((PASS + FAIL)))"; exit 1
