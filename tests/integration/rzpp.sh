#!/usr/bin/env bash
# rzpp diagnostics: each bad fixture fails with "file:line: message" naming
# the problem, and the todos example's generated file keeps its line numbers.
#   ./tests/integration/rzpp.sh [rzpp binary]
set -u
RZPP=${1:-build/rzpp}
OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT
FAIL=0
PASS=0

expect() { # expect <fixture> <line> <substring>
  local f=tests/fixtures/rzpp/$1.mettle
  local msg
  msg=$("$RZPP" "$f" "$OUT" 2>&1)
  if [ $? -ne 0 ] && [[ "$msg" == "$f:$2: "*"$3"* ]]; then
    echo "PASS  $1 -> $msg"; PASS=$((PASS + 1))
  else
    echo "FAIL  $1: want $f:$2: ...$3..., got [$msg]"; FAIL=$((FAIL + 1))
  fi
}

expect bad_variant 7 "Stop\` is not a variant of a message enum"
expect bad_component 7 "card() has no parameter \`heading\`"
expect bad_unclosed 3 "unclosed"
expect bad_not_returned 2 "must be returned"

# Line numbers survive: every source line after a literal is the same line in
# the generated file.
"$RZPP" examples/todos/app.mettle "$OUT"
SRC=$(grep -n 'fn todos_view' examples/todos/app.mettle | cut -d: -f1)
GEN=$(grep -n 'fn todos_view' "$OUT" | cut -d: -f1)
SRC2=$(grep -n '^const STYLE' examples/todos/app.mettle | cut -d: -f1)
GEN2=$(grep -n '^const STYLE' "$OUT" | cut -d: -f1)
if [ "$SRC" = "$GEN" ] && [ "$SRC2" = "$GEN2" ]; then
  echo "PASS  line numbers preserved ($SRC, $SRC2)"; PASS=$((PASS + 1))
else
  echo "FAIL  line numbers moved: $SRC->$GEN, $SRC2->$GEN2"; FAIL=$((FAIL + 1))
fi

echo
if [ $FAIL -eq 0 ]; then echo "RZPP OK ($PASS checks)"; exit 0; fi
echo "RZPP FAILED ($FAIL)"; exit 1
