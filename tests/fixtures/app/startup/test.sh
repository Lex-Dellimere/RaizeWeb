#!/usr/bin/env bash
# rz_run's startup contract (DECISIONS.md D2, A4): precedence, error report, exit
# codes 0/1/2, SIGTERM/SIGINT as a clean stop.
#   ./tests/fixtures/app/startup/test.sh [binary] [port] [rzpp]
# Run from the repository root. Uses PORT and PORT+1 (default 8077, 8078).
set -u
BIN=${1:-build/startup}
PORT=${2:-8077}
[ -n "$PORT" ] || PORT=8077
ALT=$((PORT + 1))
LOG=$(mktemp)
LOG2=$(mktemp)
PID=""
PASS=0
FAIL=0

cleanup() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then kill -9 "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; fi
  rm -f "$LOG" "$LOG2"
}
trap cleanup EXIT

ok()  { echo "PASS  $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL  $1: $2"; FAIL=$((FAIL + 1)); }
up()  { curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$1/"; }
start() {   # start <log> <env/args...>: background run, wait for "listening"
  local log=$1; shift
  env "$@" >"$log" 2>&1 &
  PID=$!
  for _ in $(seq 1 50); do grep -q listening "$log" && return 0; kill -0 "$PID" 2>/dev/null || return 1; sleep 0.1; done
  return 1
}
# stop_with <signal>: send it, wait up to 5 s, leave the exit code in RC ("hung" if not)
stop_with() {
  kill "-$1" "$PID"
  for _ in $(seq 1 100); do kill -0 "$PID" 2>/dev/null || break; sleep 0.05; done
  if kill -0 "$PID" 2>/dev/null; then RC=hung; return; fi
  wait "$PID"; RC=$?; PID=""
}

# ---- exit 1: a bad RAIZE_PORT names the variable, nothing listens ------------------
RAIZE_PORT=notaport "$BIN" >"$LOG" 2>&1; RC=$?
[ "$RC" = "1" ] && ok "bad RAIZE_PORT -> exit 1" || bad "bad RAIZE_PORT exit" "got $RC: $(cat "$LOG")"
grep -q '^startup: RAIZE_PORT: .*"notaport".* — ' "$LOG" && ok "error names RAIZE_PORT, prefixed and with a fix: $(head -1 "$LOG")" || bad "RAIZE_PORT message" "$(cat "$LOG")"
grep -q listening "$LOG" && bad "bad config" "printed listening" || ok "no listening line on a config error"
up 8077 && bad "bad config" "something answers on 8077" || ok "no socket bound on a config error"

# ---- exit 1: every declaration error is printed --------------------------------------
"$BIN" --port "$PORT" --bad-decls >"$LOG" 2>&1; RC=$?
[ "$RC" = "1" ] && ok "two declaration errors -> exit 1" || bad "bad decls exit" "got $RC: $(cat "$LOG")"
N=$(grep -c '^startup: .* — ' "$LOG")
[ "$N" = "2" ] && ok "both declaration errors printed as '<app>: <what> — <fix>'" || bad "declaration errors" "want 2 lines, got $N: $(cat "$LOG")"
grep -q 'route GET "healthz" does not start with /' "$LOG" && ok "route error says what" || bad "route error" "$(cat "$LOG")"
grep -q 'rz_every(0)' "$LOG" && ok "timer error says what" || bad "timer error" "$(cat "$LOG")"
"$BIN" --port "$PORT" --bad-static >"$LOG" 2>&1; RC=$?
[ "$RC" = "1" ] && grep -q '^startup: rz_static("/static", "tests/fixtures/app/startup/no-such-dir"): .* — ' "$LOG" \
  && ok "missing static dir -> exit 1, says where it looked" || bad "missing static dir" "rc $RC: $(cat "$LOG")"

# ---- precedence: framework default < rz_default < RAIZE_* < --port --------------------
if start "$LOG" "$BIN"; then
  grep -q "^startup: listening on 127.0.0.1:8077$" "$LOG" && ok "rz_default port used (8077)" || bad "rz_default" "$(cat "$LOG")"
  stop_with TERM
else bad "rz_default start" "$(cat "$LOG")"; fi
if start "$LOG" RAIZE_PORT="$ALT" "$BIN"; then
  grep -q "listening on 127.0.0.1:$ALT$" "$LOG" && ok "RAIZE_PORT beats rz_default" || bad "env over rz_default" "$(cat "$LOG")"
  stop_with TERM
else bad "env start" "$(cat "$LOG")"; fi
if start "$LOG" RAIZE_PORT="$ALT" "$BIN" --port "$PORT"; then
  grep -q "listening on 127.0.0.1:$PORT$" "$LOG" && ok "--port beats RAIZE_PORT" || bad "--port over env" "$(cat "$LOG")"
else bad "--port start" "$(cat "$LOG")"; fi

# ---- exit 2: port in use, and nothing says "listening" ---------------------------------
"$BIN" --port "$PORT" >"$LOG2" 2>&1; RC=$?
[ "$RC" = "2" ] && ok "port in use -> exit 2" || bad "port in use exit" "got $RC: $(cat "$LOG2")"
grep -q listening "$LOG2" && bad "port in use" "printed listening: $(cat "$LOG2")" || ok "no listening line when the bind fails"
grep -q "^startup: cannot listen on :$PORT (address in use) — " "$LOG2" && ok "bind error says what and how to fix" || bad "bind message" "$(cat "$LOG2")"
up "$PORT" && ok "the first server still answers" || bad "first server" "gone"

# ---- exit 0: SIGTERM and SIGINT stop cleanly ---------------------------------------------
stop_with TERM
[ "$RC" = "0" ] && ok "SIGTERM -> exit 0" || bad "SIGTERM" "exit $RC"
up "$PORT" && bad "after SIGTERM" "still answering" || ok "port released after SIGTERM"
if start "$LOG" "$BIN" --port "$PORT"; then
  curl -s -o /dev/null "http://127.0.0.1:$PORT/"
  stop_with INT
  [ "$RC" = "0" ] && ok "SIGINT -> exit 0" || bad "SIGINT" "exit $RC"
else bad "restart after SIGTERM" "$(cat "$LOG")"; fi

echo
if [ "$FAIL" -eq 0 ]; then echo "STARTUP OK ($PASS checks)"; exit 0; fi
echo "STARTUP FAILED ($FAIL of $((PASS + FAIL)))"; exit 1
