#!/usr/bin/env bash
# rz_channel through rz_run (P3-C1, DECISIONS F3): /socket/websocket is derived from the
# declaration; join, round trip, broadcasts, rz_broadcast from HTTP, rz_chan_conn; then
# SIGTERM with a joined socket still open stops cleanly.
#   ./tests/fixtures/app/channels/test.sh [binary] [port] [rzpp]
# Run from the repository root.
set -u
BIN=${1:-build/channels}
PORT=${2:-8084}
[ -n "$PORT" ] || PORT=8084
DIR=$(dirname "$0")
LOG=$(mktemp)
PID=""
HOLD=""
PASS=0
FAIL=0
B=http://127.0.0.1:$PORT

cleanup() {
  if [ -n "$HOLD" ] && kill -0 "$HOLD" 2>/dev/null; then kill "$HOLD" 2>/dev/null; wait "$HOLD" 2>/dev/null; fi
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; fi
  rm -f "$LOG"
}
trap cleanup EXIT

ok()  { echo "PASS  $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL  $1: $2"; FAIL=$((FAIL + 1)); }

"$BIN" --port "$PORT" >"$LOG" 2>&1 &
PID=$!
for _ in $(seq 1 50); do grep -q listening "$LOG" && break; sleep 0.1; done
grep -q "channels: listening on 127.0.0.1:$PORT" "$LOG" && ok "listening line" || { bad "listening line" "$(cat "$LOG")"; exit 1; }

CODE=$(curl -s -o /dev/null -w '%{http_code}' "$B/socket/websocket")
[ "$CODE" = "426" ] || [ "$CODE" = "400" ] && ok "GET /socket/websocket is routed (plain GET -> $CODE)" || bad "socket route" "got $CODE"

if python3 "$DIR/client.py" "$PORT"; then ok "channel client"; else bad "channel client" "see above"; fi

# A joined socket left open across SIGTERM: the server must still exit 0, promptly.
python3 - "$PORT" <<'PY' &
import os, sys, time
sys.path.insert(0, "tests/integration")
import chat_client as cc, ws_client as w
cc.PORT = w.PORT = int(sys.argv[1])
c = cc.Client()
c.reply_to(c.send("room:lobby", "phx_join", {}))
print("held", flush=True)
time.sleep(10)
PY
HOLD=$!
sleep 0.5
kill -TERM "$PID"
T0=$(date +%s%N)
RC=0
for _ in $(seq 1 30); do kill -0 "$PID" 2>/dev/null || break; sleep 0.1; done
if kill -0 "$PID" 2>/dev/null; then bad "SIGTERM with a joined socket" "still running after 3 s"
else
  wait "$PID"; RC=$?
  MS=$(( ($(date +%s%N) - T0) / 1000000 ))
  [ "$RC" -eq 0 ] && ok "SIGTERM with a joined socket open -> exit 0 in ${MS} ms" || bad "SIGTERM exit code" "rc=$RC $(cat "$LOG")"
fi
PID=""

echo
if [ "$FAIL" -eq 0 ]; then echo "CHANNELS APP OK ($PASS checks)"; exit 0; fi
echo "CHANNELS APP FAILED ($FAIL of $((PASS + FAIL)))"; exit 1
