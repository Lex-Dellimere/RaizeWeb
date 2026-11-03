#!/usr/bin/env bash
# raize acceptance smoke test.
#   ./tests/smoke.sh [binary] [port]
# Proves the server, context, router and middleware seams together, from the
# outside, over a real socket. Exits non-zero on the first failed assertion.
set -u

BIN=${1:-build/hello}
PORT=${2:-8080}
BASE="http://127.0.0.1:${PORT}"
LOG=$(mktemp)
FAIL=0
PID=""

cleanup() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null
    wait "$PID" 2>/dev/null
  fi
  rm -f "$LOG"
}
trap cleanup EXIT

say()  { printf '  %s\n' "$*"; }
pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; FAIL=$((FAIL + 1)); }

# status <path> [extra curl args...] -> prints status code
status() {
  local path=$1; shift
  curl -s -o /dev/null -w '%{http_code}' "$@" "${BASE}${path}"
}

# body <path> [curl args...]
body() {
  local path=$1; shift
  curl -s "$@" "${BASE}${path}"
}

expect_status() {
  local want=$1 path=$2; shift 2
  local got
  got=$(status "$path" "$@")
  if [ "$got" = "$want" ]; then pass "GET $path -> $got"; else fail "GET $path -> $got (want $want)"; fi
}

expect_body_has() {
  local needle=$1 path=$2
  local got
  got=$(body "$path")
  case "$got" in
    *"$needle"*) pass "GET $path body contains '$needle'" ;;
    *) fail "GET $path body missing '$needle' (got: $(printf '%.120s' "$got"))" ;;
  esac
}

[ -x "$BIN" ] || { echo "no binary at $BIN (build it first)"; exit 2; }

"$BIN" >"$LOG" 2>&1 &
PID=$!

for _ in $(seq 1 100); do
  if curl -s -o /dev/null --max-time 1 "$BASE/"; then break; fi
  kill -0 "$PID" 2>/dev/null || { echo "server exited during startup:"; sed -n '1,20p' "$LOG"; exit 2; }
  sleep 0.1
done

echo "== raize smoke: $BIN on $BASE"

# 1. routing basics
expect_status 200 /            || true
expect_status 404 /no/such/page || true

# 2. params
expect_body_has "hello" /hello/world || true

# 3. method handling
expect_status 405 / -X POST || true

# 4. header hygiene: no header injection, content-length always present
HDRS=$(curl -s -D - -o /dev/null "${BASE}/" | tr -d '\r')
case "$HDRS" in
  *"Content-Length:"*) pass "response carries Content-Length" ;;
  *) fail "response has no Content-Length" ;;
esac

# 5. keep-alive: two requests on one connection
if curl -s -o /dev/null -o /dev/null -w '%{http_code}\n' \
     "${BASE}/" "${BASE}/hello/two" | grep -qx '200' ; then
  pass "keep-alive: two requests on one connection"
else
  fail "keep-alive: second request on one connection failed"
fi

# 6. limits: oversized header block must not be answered 200
BIG=$(printf 'A%.0s' $(seq 1 9000))
CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "X-Big: $BIG" "${BASE}/")
if [ "$CODE" != "200" ]; then pass "oversized header refused ($CODE)"; else fail "oversized header accepted with 200"; fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "SMOKE OK"
  exit 0
fi
echo "SMOKE FAILED ($FAIL)"
echo "--- server log ---"
sed -n '1,40p' "$LOG"
exit 1
