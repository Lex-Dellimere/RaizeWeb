#!/usr/bin/env bash
# Resources end to end (DECISIONS.md D4): every route of the derived JSON API with its
# exact body and status, PATCH partial updates, every validation, int32/int64/bool/
# string round trips, a full layer (409), and the typed code interface (/selftest).
#   ./tests/fixtures/app/resource/test.sh [binary] [port] [rzpp]
# Run from the repository root.
set -u
BIN=${1:-build/resource}
PORT=${2:-8074}
[ -n "$PORT" ] || PORT=8074
LOG=$(mktemp)
PID=""
PASS=0
FAIL=0

cleanup() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; fi
  rm -f "$LOG"
}
trap cleanup EXIT

ok()  { echo "PASS  $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL  $1: $2"; FAIL=$((FAIL + 1)); }
# exact <label> <status> <whole-body> <curl args...>: status and body must match exactly.
exact() {
  local label=$1 status=$2 whole=$3; shift 3
  local out code body
  out=$(curl -s -w '\n%{http_code}' "$@")
  code=${out##*$'\n'}; body=${out%$'\n'*}
  if [ "$code" = "$status" ] && [ "$body" = "$whole" ]; then ok "$label -> $code ${body:0:100}"
  else bad "$label" "want $status [$whole], got $code [$body]"; fi
}

"$BIN" --port "$PORT" >"$LOG" 2>&1 &
PID=$!
for _ in $(seq 1 50); do grep -q listening "$LOG" && break; sleep 0.1; done
grep -q "resource: listening on 127.0.0.1:$PORT" "$LOG" && ok "listening line" || bad "listening line" "$(cat "$LOG")"

API=http://127.0.0.1:$PORT/api/tasks
J='-H Content-Type:application/json'
R1='{"id":1,"title":"write docs","note":"","priority":-3,"estimate":9000000000,"done":true}'

# --- create: trim, every kind, id and unknown keys ignored
exact "POST valid"          201 "$R1" $J -X POST -d '{"id":77,"title":"  write docs  ","priority":-3,"estimate":9000000000,"done":true,"extra":[1,2]}' "$API"
exact "POST {}"             400 '{"error":"invalid","fields":{"title":"can'"'"'t be blank"}}' $J -X POST -d '{}' "$API"
exact "POST blank title"    400 '{"error":"invalid","fields":{"title":"can'"'"'t be blank"}}' $J -X POST -d '{"title":"   "}' "$API"
exact "POST too short"      400 '{"error":"invalid","fields":{"title":"is too short (at least 3)"}}' $J -X POST -d '{"title":" ab "}' "$API"
exact "POST two fields"     400 '{"error":"invalid","fields":{"title":"is too long (at most 20)","note":"is too long (at most 10)"}}' $J -X POST -d '{"title":"aaaaaaaaaaaaaaaaaaaaa","note":"12345678901"}' "$API"
exact "POST wrong types"    400 '{"error":"invalid","fields":{"title":"must be a string","priority":"must be an integer","estimate":"must be an integer","done":"must be true or false"}}' $J -X POST -d '{"title":5,"priority":"x","estimate":1.5,"done":"yes"}' "$API"
exact "POST int32 range"    400 '{"error":"invalid","fields":{"priority":"is out of range (32-bit integer)"}}' $J -X POST -d '{"title":"abc","priority":2147483648}' "$API"
exact "POST not object"     400 '{"error":"body is not a JSON object"}' $J -X POST -d '[1]' "$API"
exact "POST empty body"     400 '{"error":"body is not a JSON object"}' $J -X POST "$API"

# --- read
exact "GET list (1)"        200 "[$R1]" "$API"
exact "GET /1"              200 "$R1" "$API/1"
exact "GET /999"            404 '{"error":"not found"}' "$API/999"
exact "GET /abc"            400 '{"error":"bad id"}' "$API/abc"
exact "GET /0"              400 '{"error":"bad id"}' "$API/0"

# --- update (PATCH): present keys set and validated, absent keys keep stored values
exact "PATCH note only"     200 '{"id":1,"title":"write docs","note":"hi","priority":-3,"estimate":9000000000,"done":true}' $J -X PATCH -d '{"note":" hi "}' "$API/1"
exact "PATCH int32+bool"    200 '{"id":1,"title":"write docs","note":"hi","priority":2147483647,"estimate":9000000000,"done":false}' $J -X PATCH -d '{"priority":2147483647,"done":false,"estimate":1}' "$API/1"
exact "PATCH title trim"    200 '{"id":1,"title":"ship it","note":"hi","priority":2147483647,"estimate":9000000000,"done":false}' $J -X PATCH -d '{"title":"  ship it "}' "$API/1"
exact "PATCH {}"            200 '{"id":1,"title":"ship it","note":"hi","priority":2147483647,"estimate":9000000000,"done":false}' $J -X PATCH -d '{}' "$API/1"
exact "PATCH too short"     400 '{"error":"invalid","fields":{"title":"is too short (at least 3)"}}' $J -X PATCH -d '{"title":"ab","priority":1}' "$API/1"
exact "PATCH blank"         400 '{"error":"invalid","fields":{"title":"can'"'"'t be blank"}}' $J -X PATCH -d '{"title":""}' "$API/1"
exact "PATCH wrong type"    400 '{"error":"invalid","fields":{"done":"must be true or false"}}' $J -X PATCH -d '{"done":1}' "$API/1"
exact "PATCH int32 range"   400 '{"error":"invalid","fields":{"priority":"is out of range (32-bit integer)"}}' $J -X PATCH -d '{"priority":-2147483649}' "$API/1"
exact "GET /1 unchanged"    200 '{"id":1,"title":"ship it","note":"hi","priority":2147483647,"estimate":9000000000,"done":false}' "$API/1"
exact "PATCH /999"          404 '{"error":"not found"}' $J -X PATCH -d '{"note":"x"}' "$API/999"
exact "PATCH /abc"          400 '{"error":"bad id"}' $J -X PATCH -d '{"note":"x"}' "$API/abc"
exact "PATCH not object"    400 '{"error":"body is not a JSON object"}' $J -X PATCH -d '"x"' "$API/1"

# --- custom action
exact "POST /1/finish"      200 '{"id":1,"title":"ship it","note":"hi","priority":0,"estimate":9000000000,"done":true}' -X POST "$API/1/finish"
exact "GET /1 finished"     200 '{"id":1,"title":"ship it","note":"hi","priority":0,"estimate":9000000000,"done":true}' "$API/1"
exact "POST /999/finish"    404 '{"error":"not found"}' -X POST "$API/999/finish"
exact "POST /abc/finish"    400 '{"error":"bad id"}' -X POST "$API/abc/finish"

# --- a full layer (capacity 3) answers 409 and stores nothing
exact "POST second"         201 '{"id":2,"title":"two","note":"","priority":0,"estimate":0,"done":false}' $J -X POST -d '{"title":"two"}' "$API"
exact "POST third"          201 '{"id":3,"title":"three","note":"n","priority":1,"estimate":-1,"done":false}' $J -X POST -d '{"title":"three","note":"n","priority":1,"estimate":-1}' "$API"
exact "POST full"           409 '{"error":"full"}' $J -X POST -d '{"title":"four"}' "$API"
exact "GET list (3)"        200 '[{"id":1,"title":"ship it","note":"hi","priority":0,"estimate":9000000000,"done":true},{"id":2,"title":"two","note":"","priority":0,"estimate":0,"done":false},{"id":3,"title":"three","note":"n","priority":1,"estimate":-1,"done":false}]' "$API"

# --- destroy
exact "DELETE /2"           204 '' -X DELETE "$API/2"
exact "DELETE /2 again"     404 '{"error":"not found"}' -X DELETE "$API/2"
exact "DELETE /abc"         400 '{"error":"bad id"}' -X DELETE "$API/abc"
exact "POST after delete"   201 '{"id":4,"title":"four","note":"","priority":0,"estimate":0,"done":false}' $J -X POST -d '{"title":"four"}' "$API"
exact "GET list ids"        200 '[{"id":1,"title":"ship it","note":"hi","priority":0,"estimate":9000000000,"done":true},{"id":3,"title":"three","note":"n","priority":1,"estimate":-1,"done":false},{"id":4,"title":"four","note":"","priority":0,"estimate":0,"done":false}]' "$API"

# --- the router answers verbs the resource does not declare
CODE=$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$API/1")
[ "$CODE" = "405" ] && ok "PUT /1 -> 405 (router)" || bad "PUT /1" "want 405, got $CODE"

# --- the typed code interface, natively (int32/int64/bool/string through the memory layer)
SELF='create=0 id=1 get=0 [1 first|n p=-7 e=5000000000 done]
update=0 get=0 [1 renamed| p=2147483647 e=5000000000 open]
bad update=-2 n=2 title=is too short (at least 3) note=is too long (at most 10) code=-2 get=0 [1 renamed| p=2147483647 e=5000000000 open]
finish=0 get=0 [1 renamed| p=0 e=5000000000 done]
second=0 full=-5 code=-5 count=2 read=2 last=two
missing get=-3 update=-3 finish=-3 destroy=-3
destroy=0 count=1 misuse=-1'
exact "GET /selftest"       200 "$SELF" "http://127.0.0.1:$PORT/selftest"

kill -0 "$PID" 2>/dev/null && ok "server still up" || bad "server" "exited: $(cat "$LOG")"

echo
if [ $FAIL -eq 0 ]; then echo "RESOURCE OK ($PASS checks)"; exit 0; fi
echo "RESOURCE FAILED ($FAIL of $((PASS + FAIL)))"; exit 1
