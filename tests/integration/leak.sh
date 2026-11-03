#!/usr/bin/env bash
# raize integration: leak check under load.
#   ./tests/integration/leak.sh [binary] [port] [requests]
# A request path that allocates must free everything it allocated. 2 000
# keep-alive requests should leave the server's RSS flat; growth over the
# threshold means a per-request leak (arena, header copy, response body, ...).
set -u

BIN=${1:-build/hello}
PORT=${2:-8080}
N=${3:-2000}
LIMIT_KB=${LIMIT_KB:-8192}
BASE="http://127.0.0.1:${PORT}"
LOG=$(mktemp)
URLS=$(mktemp)
FAIL=0
PID=""

cleanup() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; fi
  rm -f "$LOG" "$URLS"
}
trap cleanup EXIT

pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; FAIL=$((FAIL + 1)); }

rss_kb() { awk '/^VmRSS:/{print $2}' "/proc/$1/status" 2>/dev/null || echo 0; }
vsz_kb() { awk '/^VmSize:/{print $2}' "/proc/$1/status" 2>/dev/null || echo 0; }

[ -x "$BIN" ] || { echo "no binary at $BIN"; exit 2; }

"$BIN" --port "$PORT" >"$LOG" 2>&1 &
PID=$!
READY=0
for _ in $(seq 1 100); do
  if curl -s -o /dev/null --max-time 1 "${BASE}/"; then READY=1; break; fi
  kill -0 "$PID" 2>/dev/null || { echo "server exited:"; head -20 "$LOG"; exit 2; }
  sleep 0.1
done
[ "$READY" = "1" ] || { echo "server never answered on ${BASE}"; head -20 "$LOG"; exit 2; }

# Warm up so one-time allocations (router, templates, static index) are done.
for _ in $(seq 1 50); do curl -s -o /dev/null "${BASE}/"; done

RSS0=$(rss_kb "$PID")
VSZ0=$(vsz_kb "$PID")

for _ in $(seq 1 "$N"); do printf 'url = "%s/"\n' "$BASE"; done >"$URLS"
curl -s -K "$URLS" > /dev/null

RSS1=$(rss_kb "$PID")
VSZ1=$(vsz_kb "$PID")
GROWTH=$((RSS1 - RSS0))
VSZ_GROWTH=$((VSZ1 - VSZ0))

echo "== raize leak check: $N requests on $BASE"
pass "rss ${RSS0} kB -> ${RSS1} kB (growth ${GROWTH} kB)"
pass "vsz ${VSZ0} kB -> ${VSZ1} kB (growth ${VSZ_GROWTH} kB)"

if [ "$GROWTH" -le "$LIMIT_KB" ]; then
  pass "rss growth within ${LIMIT_KB} kB"
else
  fail "rss grew ${GROWTH} kB over ${N} requests (limit ${LIMIT_KB} kB): a per-request leak"
fi

if [ "$VSZ_GROWTH" -le "$LIMIT_KB" ]; then
  pass "address space stable"
else
  fail "address space grew ${VSZ_GROWTH} kB (a thread or a large mapping leaked)"
fi

if kill -0 "$PID" 2>/dev/null; then pass "server still alive"; else fail "server died under load"; fi

echo
if [ "$FAIL" -eq 0 ]; then echo "LEAK OK"; exit 0; fi
echo "LEAK FAILED ($FAIL)"
tail -5 "$LOG"
exit 1
