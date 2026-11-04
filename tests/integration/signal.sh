#!/usr/bin/env bash
# raize integration: Signals (examples/todos) over real sockets.
#   ./tests/integration/signal.sh [binary] [port]
set -u

BIN=${1:-build/todos}
PORT=${2:-8070}
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

python3 "$(dirname "$0")/signal_client.py" "$PORT"
RC=$?
if ! kill -0 "$PID" 2>/dev/null; then
  echo "FAIL  server exited:"; cat "$LOG"; exit 1
fi
exit $RC
