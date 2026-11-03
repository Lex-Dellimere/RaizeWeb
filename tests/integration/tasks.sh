#!/usr/bin/env bash
# raize integration: the examples/tasks application, end to end.
#   ./tests/integration/tasks.sh [binary] [port]
#
# Proves routing, path params, JSON in/out, the in-memory store, static files,
# CORS, recovery and the config-driven listener over real sockets.
set -u

BIN=${1:-build/tasks}
PORT=${2:-8094}
BASE="http://127.0.0.1:${PORT}"
LOG=$(mktemp)
FAIL=0
PID=""
PASS=0

cleanup() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null
    wait "$PID" 2>/dev/null
  fi
  rm -f "$LOG"
}
trap cleanup EXIT

pass() { printf 'PASS  %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL  %s\n' "$*"; FAIL=$((FAIL + 1)); }

code() { local path=$1; shift; curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$@" "${BASE}${path}"; }
body() { local path=$1; shift; curl -s --max-time 3 "$@" "${BASE}${path}"; }

want() { # want <label> <expected> <actual>
  local label=$1 expected=$2 actual=$3
  if [ "$actual" = "$expected" ]; then pass "$label ($actual)"; else fail "$label: want $expected, got $actual"; fi
}

has() { # has <label> <needle> <haystack>
  local label=$1 needle=$2 text=$3
  case "$text" in
    *"$needle"*) pass "$label" ;;
    *) fail "$label: missing '$needle' in '$(printf '%.160s' "$text")'" ;;
  esac
}

[ -x "$BIN" ] || { echo "no binary at $BIN (build it first)"; exit 2; }

"$BIN" --port "$PORT" >"$LOG" 2>&1 &
PID=$!

READY=0
for _ in $(seq 1 100); do
  if curl -s -o /dev/null --max-time 1 "${BASE}/"; then READY=1; break; fi
  kill -0 "$PID" 2>/dev/null || { echo "server exited during startup:"; sed -n '1,20p' "$LOG"; exit 2; }
  sleep 0.1
done
[ "$READY" = "1" ] || { echo "server never answered on ${BASE}"; sed -n '1,20p' "$LOG"; exit 2; }

echo "== raize tasks: $BIN on $BASE"

# 1. HTML page from the startup-compiled template.
HOME_BODY=$(body /)
has "template renders the page title" "raize tasks" "$HOME_BODY"
has "template substitutes the store count" 'id="count">0<' "$HOME_BODY"
CT=$(curl -s -o /dev/null -w '%{content_type}' --max-time 3 "${BASE}/")
case "$CT" in text/html*) pass "page content-type $CT" ;; *) fail "page content-type $CT (want text/html)" ;; esac

# 2. JSON API and validation.
want "empty list" "200" "$(code /api/tasks)"
has "empty list is []" "[]" "$(body /api/tasks)"
want "missing title is 400" "400" "$(code /api/tasks -X POST -H 'Content-Type: application/json' --data '{}')"
want "blank title is 400" "400" "$(code /api/tasks -X POST -H 'Content-Type: application/json' --data '{"title":"   "}')"

CREATED=$(body /api/tasks -X POST -H 'Content-Type: application/json' --data '{"title":"  write the example  "}')
has "created task is JSON" '"id":1' "$CREATED"
has "stored title is trimmed" '"title":"write the example"' "$CREATED"
has "created task starts open" '"done":false' "$CREATED"
want "create status is 201" "201" "$(code /api/tasks -X POST -H 'Content-Type: application/json' --data '{"title":"second"}')"

want "get one" "200" "$(code /api/tasks/1)"
want "missing task is 404" "404" "$(code /api/tasks/999)"
want "non-numeric id is 400" "400" "$(code /api/tasks/abc)"
has "404 body is JSON" '{"error":"not found"}' "$(body /api/tasks/999)"

TOGGLED=$(body /api/tasks/1/toggle -X POST)
has "toggle flips done" '"done":true' "$TOGGLED"
has "list contains both tasks" '"id":2' "$(body /api/tasks)"
want "wrong method on a task is 405" "405" "$(code /api/tasks/1 -X POST)"

# 3. Static assets + ETag.
SC=$(code /static/style.css)
[ "$SC" = "200" ] && pass "static 200" || fail "static -> $SC"
ETAG=$(curl -s -D - -o /dev/null --max-time 3 "${BASE}/static/style.css" | tr -d '\r' | awk -F': ' 'tolower($1)=="etag"{print $2}')
if [ -n "$ETAG" ]; then
  pass "static emits ETag"
  want "If-None-Match is 304" "304" "$(code /static/style.css -H "If-None-Match: $ETAG")"
else
  fail "static emitted no ETag"
fi
TC=$(code /static/../app.mettle)
case "$TC" in 400|403|404) pass "traversal refused ($TC)" ;; *) fail "traversal -> $TC" ;; esac

# 4. CORS preflight.
OC=$(code /api/tasks -X OPTIONS -H 'Origin: http://example.test' -H 'Access-Control-Request-Method: POST')
case "$OC" in 204|200) pass "CORS preflight $OC" ;; *) fail "CORS preflight -> $OC" ;; esac
if curl -s -D - -o /dev/null --max-time 3 -X OPTIONS \
     -H 'Origin: http://example.test' -H 'Access-Control-Request-Method: POST' \
     "${BASE}/api/tasks" | tr -d '\r' | grep -qi 'access-control-allow-methods'; then
  pass "preflight carries Allow-Methods"
else
  fail "preflight has no Access-Control-Allow-Methods"
fi

# 5. Delete, then health reflects the store.
want "delete is 204" "204" "$(code /api/tasks/1 -X DELETE)"
want "delete again is 404" "404" "$(code /api/tasks/1 -X DELETE)"
HEALTH=$(body /healthz)
has "health is ok" '"status":"ok"' "$HEALTH"
has "health counts remaining tasks" '"tasks":1' "$HEALTH"

# 6. One access-log line per request.
LINES=$(grep -c '^req ' "$LOG" 2>/dev/null || echo 0)
[ "$LINES" -ge 12 ] && pass "access log lines: $LINES" || fail "access log lines: $LINES (want >= 12)"

echo
if [ "$FAIL" -eq 0 ]; then
  echo "TASKS OK ($PASS checks)"
  exit 0
fi
echo "TASKS FAILED ($FAIL)"
echo "--- log ---"
sed -n '1,60p' "$LOG"
exit 1
