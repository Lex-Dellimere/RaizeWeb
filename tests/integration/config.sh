#!/usr/bin/env bash
# raize integration: configuration drives bind/port/limits, not literals.
#   ./tests/integration/config.sh [binary] [port] [rz_run-binary]
#
# Asserts:
#   1. RAIZE_PORT sets the listen port (the startup log names it).
#   2. RAIZE_MAX_BODY_BYTES=1024 is enforced: a 2 KB POST is 413, a small POST is not.
#   3. an explicit --port beats RAIZE_PORT (argv > env > default).
#   4. a bad RAIZE_PORT is refused at startup with the variable named in the
#      error, and no socket is bound.
#   5. (with an rz_run app as the third argument, one that calls
#      rz_default(app, "port", "8077")) RAIZE_PORT beats rz_default: operators
#      override the code (D2 reversed the old "program set beats env").
set -u

BIN=${1:-build/site}
PORT=${2:-8093}
RZRUN=${3:-}
FAIL=0
LOG=""
PID=""

cleanup() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; fi
  [ -n "$LOG" ] && rm -f "$LOG"
}
trap cleanup EXIT

pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; FAIL=$((FAIL + 1)); }
code() { local path=$1; shift; curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$@" "http://127.0.0.1:${PORT}${path}"; }

wait_up() { # $1 = port
  local p=$1
  for _ in $(seq 1 100); do
    curl -s -o /dev/null --max-time 1 "http://127.0.0.1:${p}/" && return 0
    kill -0 "$PID" 2>/dev/null || return 1
    sleep 0.1
  done
  return 1
}

[ -x "$BIN" ] || { echo "no binary at $BIN (build it first)"; exit 2; }

# ---- 1 + 2: env drives port and the body cap -------------------------------
LOG=$(mktemp)
RAIZE_PORT=$PORT RAIZE_MAX_BODY_BYTES=1024 "$BIN" >"$LOG" 2>&1 &
PID=$!
echo "== raize config: $BIN, RAIZE_PORT=$PORT RAIZE_MAX_BODY_BYTES=1024"
if wait_up "$PORT"; then
  pass "listens on the port from RAIZE_PORT ($PORT)"
else
  fail "did not answer on $PORT"; sed -n 1,10p "$LOG"; exit 1
fi
if grep -q "$PORT" "$LOG"; then pass "startup log names the configured port"; else fail "startup log does not mention $PORT"; fi

SMALL=$(printf '{"msg":"%s"}' "$(printf 'a%.0s' $(seq 1 10))")
BIG=$(printf '{"msg":"%s"}' "$(printf 'a%.0s' $(seq 1 2000))")
SC=$(code /api/echo -X POST -H 'Content-Type: application/json' --data-binary "$SMALL")
case "$SC" in 200|400|404|405) pass "small POST accepted as a request ($SC)" ;; 413) fail "small POST hit the body cap ($SC)" ;; *) fail "small POST -> $SC" ;; esac
BC=$(code /api/echo -X POST -H 'Content-Type: application/json' --data-binary "$BIG")
[ "$BC" = "413" ] && pass "2 KB POST refused with 413 under RAIZE_MAX_BODY_BYTES=1024" || fail "2 KB POST -> $BC (want 413)"
kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; PID=""
rm -f "$LOG"

# ---- 3: argv beats env -----------------------------------------------------
LOG=$(mktemp)
ALT=$((PORT + 1))
RAIZE_PORT=$((PORT + 2)) "$BIN" --port "$ALT" >"$LOG" 2>&1 &
PID=$!
echo "== precedence: RAIZE_PORT=$((PORT + 2)) but --port $ALT"
if wait_up "$ALT"; then pass "--port wins over RAIZE_PORT (listening on $ALT)"; else fail "--port did not win (nothing on $ALT)"; fi
if curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$((PORT + 2))/"; then fail "also listening on the env port $((PORT + 2))"; else pass "not listening on the overridden env port"; fi
kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; PID=""
rm -f "$LOG"

# ---- 4: invalid config is refused before binding ---------------------------
LOG=$(mktemp)
RAIZE_PORT=notaport "$BIN" >"$LOG" 2>&1
RC=$?
if [ "$RC" -ne 0 ]; then pass "invalid RAIZE_PORT refused at startup (exit $RC)"; else fail "invalid RAIZE_PORT accepted"; fi
if grep -qi "RAIZE_PORT" "$LOG"; then pass "error names the offending variable"; else fail "error does not name RAIZE_PORT: $(head -2 "$LOG" | tr '\n' ' ')"; fi
if curl -s -o /dev/null --max-time 1 "http://127.0.0.1:${PORT}/"; then fail "a socket was bound despite invalid config"; else pass "no socket bound on invalid config"; fi
rm -f "$LOG"

# ---- 5: RAIZE_PORT beats rz_default (rz_run apps) ----------------------------
if [ -n "$RZRUN" ]; then
  [ -x "$RZRUN" ] || { echo "no binary at $RZRUN (build it first)"; exit 2; }
  LOG=$(mktemp)
  RAIZE_PORT=$PORT "$RZRUN" >"$LOG" 2>&1 &
  PID=$!
  echo "== precedence: $RZRUN declares rz_default port 8077, RAIZE_PORT=$PORT"
  if wait_up "$PORT"; then pass "RAIZE_PORT beats rz_default (listening on $PORT)"; else fail "RAIZE_PORT did not beat rz_default: $(head -2 "$LOG" | tr '\n' ' ')"; fi
  if curl -s -o /dev/null --max-time 1 "http://127.0.0.1:8077/"; then fail "also listening on the rz_default port 8077"; else pass "not listening on the rz_default port"; fi
  kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; RC=$?; PID=""
  [ "$RC" = "0" ] && pass "SIGTERM -> exit 0" || fail "SIGTERM -> exit $RC (want 0)"
  rm -f "$LOG"
fi

echo
if [ "$FAIL" -eq 0 ]; then echo "CONFIG OK"; exit 0; fi
echo "CONFIG FAILED ($FAIL)"
exit 1
