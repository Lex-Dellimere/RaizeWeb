#!/usr/bin/env bash
# raize integration: WebSockets on the epoll loop (tests/fixtures/poll/ws_echo).
#   ./tests/integration/ws.sh [binary] [port]
#
# Starts the echo server, runs the stdlib-only Python client against it, and
# fails if the server died along the way.
set -u

BIN=${1:-build/ws_echo}
PORT=${2:-8095}
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

python3 "$(dirname "$0")/ws_client.py" "$PORT"
RC=$?
if ! kill -0 "$PID" 2>/dev/null; then
  echo "FAIL  server exited:"; cat "$LOG"; exit 1
fi
exit $RC
