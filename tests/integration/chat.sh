#!/usr/bin/env bash
# raize integration: Phoenix channels (examples/chat) over real sockets.
#   ./tests/integration/chat.sh [binary] [port]
set -u

BIN=${1:-build/chat}
PORT=${2:-8090}
LOG=$(mktemp)
PID=""

cleanup() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null
    wait "$PID" 2>/dev/null
  fi
  rm -f "$LOG"
}
trap cleanup EXIT

"$BIN" "$PORT" >"$LOG" 2>&1 &
PID=$!
for _ in $(seq 1 50); do
  grep -q listening "$LOG" && break
  sleep 0.1
done

python3 "$(dirname "$0")/chat_client.py" "$PORT"
RC=$?
if ! kill -0 "$PID" 2>/dev/null; then
  echo "FAIL  server exited:"; cat "$LOG"; exit 1
fi
exit $RC
