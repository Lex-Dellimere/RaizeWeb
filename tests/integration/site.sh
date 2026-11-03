#!/usr/bin/env bash
# raize integration: middleware + template + static + router together.
#   ./tests/integration/site.sh [binary] [port]
# Expects examples/site/app.mettle:
#   GET  /                200 text/html, body contains "raize site"
#   GET  /static/style.css 200 text/css + Cache-Control + ETag
#   GET  /static/style.css with If-None-Match  -> 304
#   GET  /static/../secret 404 (traversal refused)
#   POST /api/echo         200 application/json, echoes {"msg":...}
#   GET  /api/boom         500, generic body, detail only in the log
#   OPTIONS /api/echo      204 + Access-Control-Allow-*
#   every request logs one line
set -u

BIN=${1:-build/site}
PORT=${2:-8081}
BASE="http://127.0.0.1:${PORT}"
LOG=$(mktemp)
FAIL=0
PID=""

cleanup() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; fi
  rm -f "$LOG"
}
trap cleanup EXIT

pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; FAIL=$((FAIL + 1)); }

# code <path> [curl args...] -> status code (exactly one URL, always)
code() { local p=$1; shift; curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$@" "${BASE}${p}"; }

[ -x "$BIN" ] || { echo "no binary at $BIN (build it first)"; exit 2; }
"$BIN" --port "$PORT" >"$LOG" 2>&1 &
PID=$!
READY=0
for _ in $(seq 1 100); do
  if curl -s -o /dev/null --max-time 1 "${BASE}/"; then READY=1; break; fi
  kill -0 "$PID" 2>/dev/null || { echo "server exited during startup:"; head -20 "$LOG"; exit 2; }
  sleep 0.1
done
[ "$READY" = "1" ] || { echo "server never answered on ${BASE}"; head -20 "$LOG"; exit 2; }
echo "== raize site: $BIN on $BASE"

# 1. template
BODY=$(curl -s --max-time 3 "${BASE}/")
case "$BODY" in *"raize site"*) pass "template renders index" ;; *) fail "template body missing 'raize site'" ;; esac
CT=$(curl -s -o /dev/null -w '%{content_type}' --max-time 3 "${BASE}/")
case "$CT" in text/html*) pass "content-type $CT" ;; *) fail "content-type $CT (want text/html)" ;; esac

# 2. static + cache validator
SC=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "${BASE}/static/style.css")
[ "$SC" = "200" ] && pass "static 200" || fail "static -> $SC"
SCT=$(curl -s -o /dev/null -w '%{content_type}' --max-time 3 "${BASE}/static/style.css")
case "$SCT" in text/css*) pass "static content-type $SCT" ;; *) fail "static content-type $SCT" ;; esac
ETAG=$(curl -s -D - -o /dev/null --max-time 3 "${BASE}/static/style.css" | tr -d '\r' | awk -F': ' 'tolower($1)=="etag"{print $2}')
if [ -n "$ETAG" ]; then
  pass "static emits ETag"
  NC=$(code "/static/style.css" -H "If-None-Match: $ETAG")
  [ "$NC" = "304" ] && pass "If-None-Match -> 304" || fail "If-None-Match -> $NC (want 304)"
else
  fail "static emitted no ETag"
fi
AC=$(curl -s -D - -o /dev/null --max-time 3 "${BASE}/static/style.css" | tr -d '\r' | grep -ci 'cache-control')
[ "$AC" -ge 1 ] && pass "static emits Cache-Control" || fail "static has no Cache-Control"

# 3. traversal
TC=$(code "/static/../secret")
case "$TC" in 400|403|404) pass "traversal refused ($TC)" ;; *) fail "traversal -> $TC" ;; esac

# 4. JSON route
JC=$(curl -s -o /tmp/raize_echo -w '%{http_code}' --max-time 3 -X POST \
      -H 'Content-Type: application/json' -d '{"msg":"hi"}' "${BASE}/api/echo")
[ "$JC" = "200" ] && pass "POST /api/echo 200" || fail "POST /api/echo -> $JC"
if grep -q '"msg"' /tmp/raize_echo 2>/dev/null; then pass "JSON body echoed"; else fail "JSON body not echoed: $(head -c 120 /tmp/raize_echo 2>/dev/null)"; fi
JCT=$(curl -s -o /dev/null -w '%{content_type}' --max-time 3 -X POST -d '{"msg":"hi"}' "${BASE}/api/echo")
case "$JCT" in application/json*) pass "JSON content-type $JCT" ;; *) fail "JSON content-type $JCT" ;; esac

# 5. recovery
BC=$(code "/api/boom")
[ "$BC" = "500" ] && pass "handler error -> 500" || fail "/api/boom -> $BC (want 500)"
if grep -qi 'boom' "$LOG"; then pass "failure detail logged"; else fail "no log line for the failure"; fi

# 6. CORS preflight
OC=$(curl -s -o /tmp/raize_cors -w '%{http_code}' --max-time 3 -X OPTIONS \
      -H 'Origin: http://example.test' -H 'Access-Control-Request-Method: POST' "${BASE}/api/echo")
case "$OC" in 204|200) pass "CORS preflight $OC" ;; *) fail "CORS preflight -> $OC" ;; esac
# A CORS preflight carries both Origin and Access-Control-Request-Method;
# a bare OPTIONS is an ordinary request and correctly returns only Allow.
if curl -s -D - -o /dev/null --max-time 3 -X OPTIONS \
     -H 'Origin: http://example.test' \
     -H 'Access-Control-Request-Method: POST' \
     "${BASE}/api/echo" | tr -d '\r' | grep -qi 'access-control-allow-methods'; then
  pass "preflight carries Allow-Methods"
else
  fail "preflight has no Access-Control-Allow-Methods"
fi

# 7. one log line per request (>= 6 requests so far)
LINES=$(grep -c . "$LOG" 2>/dev/null || echo 0)
[ "$LINES" -ge 6 ] && pass "request log lines: $LINES" || fail "request log lines: $LINES (want >= 6)"

rm -f /tmp/raize_echo /tmp/raize_cors
echo
if [ "$FAIL" -eq 0 ]; then echo "SITE OK"; exit 0; fi
echo "SITE FAILED ($FAIL)"
echo "--- log ---"; sed -n '1,40p' "$LOG"
exit 1
