#!/usr/bin/env bash
# raize HTTP edge cases over raw sockets.
#   ./tests/integration/http_edges.sh [binary] [port]
# These are the requests a framework usually gets wrong: duplicate framing
# headers, obs-fold, bare LF, oversized lines. Each must be refused with a 4xx
# and the connection must not be reused. Starts its own server.
set -u

BIN=${1:-build/hello}
PORT=${2:-8080}
LOG=$(mktemp)
PID=""
FAIL=0

cleanup() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; fi
  rm -f "$LOG"
}
trap cleanup EXIT

say()  { printf '  %s\n' "$*"; }
pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; FAIL=$((FAIL + 1)); }

# raw <payload-with-\r\n-escapes> -> prints the status line (or "no-response")
raw() {
  local payload=$1
  local out
  out=$(
    exec 3<>"/dev/tcp/127.0.0.1/${PORT}" || exit 3
    printf '%b' "$payload" >&3
    timeout 2 head -c 400 <&3
    exec 3<&- 3>&-
  )
  if [ -z "$out" ]; then echo "no-response"; return; fi
  printf '%s' "$out" | head -n 1
}

expect_code() {
  local want=$1 name=$2 payload=$3
  local line
  line=$(raw "$payload")
  case "$line" in
    HTTP/1.*" $want "*) pass "$name -> $line" ;;
    no-response)         fail "$name -> connection closed with no response (want $want)" ;;
    *)                   fail "$name -> $line (want $want)" ;;
  esac
}

[ -x "$BIN" ] || { echo "no binary at $BIN (build it first)"; exit 2; }
"$BIN" --port "$PORT" >"$LOG" 2>&1 &
PID=$!
READY=0
for _ in $(seq 1 100); do
  if curl -s -o /dev/null --max-time 1 "http://127.0.0.1:${PORT}/"; then READY=1; break; fi
  kill -0 "$PID" 2>/dev/null || { echo "server exited during startup:"; head -20 "$LOG"; exit 2; }
  sleep 0.1
done
[ "$READY" = "1" ] || { echo "server never answered on ${PORT}"; head -20 "$LOG"; exit 2; }

# Baseline: a well-formed request must be answered 200 by the example app.
BASE='GET / HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n'
expect_code 200 "baseline GET" "$BASE"

# Framing / smuggling
expect_code 400 "duplicate Content-Length" \
  'POST / HTTP/1.1\r\nHost: t\r\nContent-Length: 5\r\nContent-Length: 7\r\n\r\nhello'
expect_code 400 "Transfer-Encoding + Content-Length" \
  'POST / HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\nContent-Length: 5\r\n\r\n5\r\nhello\r\n0\r\n\r\n'
expect_code 400 "obs-fold (header continuation)" \
  'GET / HTTP/1.1\r\nHost: t\r\nX-A: one\r\n two\r\n\r\n'
expect_code 400 "bare LF line endings" \
  'GET / HTTP/1.1\nHost: t\n\n'
expect_code 400 "Content-Length with a sign" \
  'POST / HTTP/1.1\r\nHost: t\r\nContent-Length: +5\r\n\r\nhello'
expect_code 400 "Content-Length with trailing junk" \
  'POST / HTTP/1.1\r\nHost: t\r\nContent-Length: 5x\r\n\r\nhello'
expect_code 400 "space before colon" \
  'GET / HTTP/1.1\r\nHost : t\r\n\r\n'

# Limits
LONG=$(printf 'a%.0s' $(seq 1 9000))
expect_code 431 "header block over the cap" \
  "GET / HTTP/1.1\r\nHost: t\r\nX-Big: ${LONG}\r\n\r\n"

TARGET=$(printf 'a%.0s' $(seq 1 5000))
expect_code 414 "request target over the cap" \
  "GET /${TARGET} HTTP/1.1\r\nHost: t\r\n\r\n"

# A body over the cap must be refused before it is buffered.
expect_code 413 "body over the cap" \
  'POST / HTTP/1.1\r\nHost: t\r\nContent-Length: 2097152\r\n\r\n'

echo
if [ "$FAIL" -eq 0 ]; then echo "EDGES OK"; exit 0; fi
echo "EDGES FAILED ($FAIL)"
exit 1
