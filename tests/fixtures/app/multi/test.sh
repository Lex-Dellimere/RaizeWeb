#!/usr/bin/env bash
# A multi-file app through rzpp's entry mode (P3-C3, DECISIONS D1, reports/007): the
# generated files and rewritten imports, then the Signal, resource and plain handler
# from three different source files.
#   ./tests/fixtures/app/multi/test.sh [binary] [port] [rzpp]
# Run from the repository root.
set -u
BIN=${1:-build/multi}
PORT=${2:-8073}
[ -n "$PORT" ] || PORT=8073
DIR=$(dirname "$0")
LOG=$(mktemp)
PID=""
PASS=0
FAIL=0
B=http://127.0.0.1:$PORT

cleanup() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; fi
  rm -f "$LOG"
}
trap cleanup EXIT

ok()  { echo "PASS  $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL  $1: $2"; FAIL=$((FAIL + 1)); }
# exact <label> <status> <whole-body> <curl args...>
exact() {
  local label=$1 status=$2 whole=$3; shift 3
  local out code body
  out=$(curl -s -w '\n%{http_code}' "$@")
  code=${out##*$'\n'}; body=${out%$'\n'*}
  if [ "$code" = "$status" ] && [ "$body" = "$whole" ]; then ok "$label -> $code ${body:0:80}"
  else bad "$label" "want $status [$whole], got $code [$body]"; fi
}
# same_line <file> <line> <text>: the generated file has exactly <text> on <line>.
same_line() {
  local got
  got=$(sed -n "$2p" "$1")
  [ "$got" = "$3" ] && ok "$1:$2 is [$3]" || bad "$1:$2" "want [$3], got [$got]"
}

# --- what entry mode generated (the Makefile ran `rzpp app.mettle`)
for f in app counter notes; do
  [ -f "$DIR/$f.gen.mettle" ] && ok "$f.gen.mettle generated" || bad "$f.gen.mettle" "missing"
done
[ ! -e "$DIR/util.gen.mettle" ] && ok "util.mettle (no decorators/html) left alone" || bad "util.gen.mettle" "should not exist"
same_line "$DIR/app.gen.mettle" 12 'import "counter.gen";'
same_line "$DIR/app.gen.mettle" 13 'import "notes.gen";'
same_line "$DIR/app.gen.mettle" 14 'import "util";'
same_line "$DIR/counter.gen.mettle" 7 'import "util";'
n=$(grep -n '^fn counter_view' "$DIR/counter.mettle" | cut -d: -f1)
same_line "$DIR/counter.gen.mettle" "$n" 'fn counter_view(s: Counter*) -> RzHtml* {'
grep -A1 '^export fn counter_signal' "$DIR/counter.gen.mettle" | grep -q '  multi_counter__resources();' \
  && grep -A1 '^fn multi_counter__resources' "$DIR/counter.gen.mettle" | grep -q 'tally_resource();' \
  && ok "counter_signal builds tally_resource() during declaration (A5)" || bad "A5" "counter_signal does not build tally_resource"

# --- the app
"$BIN" --port "$PORT" >"$LOG" 2>&1 &
PID=$!
for _ in $(seq 1 50); do grep -q listening "$LOG" && break; sleep 0.1; done
grep -q "multi: listening on 127.0.0.1:$PORT" "$LOG" && ok "listening line" || { bad "listening line" "$(cat "$LOG")"; exit 1; }

page=$(curl -s "$B/counter")
[[ "$page" == *'<p class="n">7</p>'* ]] && ok "GET /counter (Signal from counter.mettle, mount reads util)" || bad "GET /counter" "${page:0:300}"
exact "GET /hello (util imported as is)" 200 "hello from util start=7" "$B/hello"
J='-H Content-Type:application/json'
exact "POST note (resource from notes.mettle)" 201 '{"id":1,"text":"hi"}' $J -X POST -d '{"text":"  hi  "}' "$B/api/notes"
exact "POST blank note" 400 '{"error":"invalid","fields":{"text":"can'"'"'t be blank"}}' $J -X POST -d '{"text":""}' "$B/api/notes"
exact "GET notes" 200 '[{"id":1,"text":"hi"}]' "$B/api/notes"

if python3 "$DIR/client.py" "$PORT"; then ok "multi client"; else bad "multi client" "see above"; fi
kill -0 "$PID" 2>/dev/null && ok "server still up" || bad "server" "exited: $(cat "$LOG")"

echo
if [ "$FAIL" -eq 0 ]; then echo "MULTI APP OK ($PASS checks)"; exit 0; fi
echo "MULTI APP FAILED ($FAIL of $((PASS + FAIL)))"; exit 1
