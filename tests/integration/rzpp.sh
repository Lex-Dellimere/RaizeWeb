#!/usr/bin/env bash
# rzpp diagnostics: every tests/fixtures/rzpp/bad_*.mettle fails with
# "file:line: message". Each fixture states what it expects on a last line:
#   // expect: <line>: <substring of the message>
# and the todos example's generated file keeps its line numbers.
#   ./tests/integration/rzpp.sh [rzpp binary]
set -u
RZPP=${1:-build/rzpp}
OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT
FAIL=0
PASS=0

for f in tests/fixtures/rzpp/bad_*.mettle; do
  name=$(basename "$f" .mettle)
  spec=$(grep -m1 '^// expect: ' "$f" | sed 's|^// expect: ||')
  if [ -z "$spec" ]; then echo "FAIL  $name: no '// expect: <line>: <text>' line"; FAIL=$((FAIL + 1)); continue; fi
  line=${spec%%:*}
  text=${spec#*: }
  msg=$("$RZPP" "$f" "$OUT" 2>&1)
  if [ $? -ne 0 ] && [[ "$msg" == "$f:$line: "*"$text"* ]]; then
    echo "PASS  $name -> $msg"; PASS=$((PASS + 1))
  else
    echo "FAIL  $name: want $f:$line: ...$text..., got [$msg]"; FAIL=$((FAIL + 1))
  fi
done

# Line numbers survive: every source line after a literal or a decorator is the
# same line in the generated file.
same_line() { # same_line <source> <pattern>
  "$RZPP" "$1" "$OUT" || return 1
  local a b
  a=$(grep -n "$2" "$1" | head -1 | cut -d: -f1)
  b=$(grep -n "$2" "$OUT" | head -1 | cut -d: -f1)
  if [ -n "$a" ] && [ "$a" = "$b" ]; then
    echo "PASS  $1: line of /$2/ preserved ($a)"; PASS=$((PASS + 1))
  else
    echo "FAIL  $1: /$2/ moved: $a -> $b"; FAIL=$((FAIL + 1))
  fi
}
same_line examples/todos/app.mettle 'fn todos_view'
same_line examples/todos/app.mettle '^const STYLE'
same_line tests/fixtures/app/slice/app.mettle '^struct Note'
same_line tests/fixtures/app/slice/app.mettle '^fn slice_app'

# Good fixtures: tests/fixtures/rzpp/ok_*.mettle must generate, and every
#   // static: <text>
# line names a static string the generated file holds exactly ("<text>").
for f in tests/fixtures/rzpp/ok_*.mettle; do
  name=$(basename "$f" .mettle)
  if ! msg=$("$RZPP" "$f" "$OUT" 2>&1); then echo "FAIL  $name: rzpp failed: $msg"; FAIL=$((FAIL + 1)); continue; fi
  while IFS= read -r want; do
    if grep '^const RZS_' "$OUT" | grep -qF "\"$want\""; then
      echo "PASS  $name: static \"$want\""; PASS=$((PASS + 1))
    else
      echo "FAIL  $name: no static \"$want\" in: $(grep '^const RZS_' "$OUT")"; FAIL=$((FAIL + 1))
    fi
  done < <(grep '^// static: ' "$f" | sed 's|^// static: ||')
done

# Entry mode (reports/007): every local import that needs it is generated beside its
# source, imports are rewritten on the same line, and a cycle ends.
check() { # check <label> <command...>
  local label=$1; shift
  if "$@"; then echo "PASS  $label"; PASS=$((PASS + 1)); else echo "FAIL  $label"; FAIL=$((FAIL + 1)); fi
}
E=tests/fixtures/rzpp/entry
check "entry mode ends on the cycle a -> plain -> b -> a" timeout 10 "$RZPP" $E/cycle/a.mettle
check "a.gen.mettle:4 imports plain.gen" [ "$(sed -n 4p $E/cycle/a.gen.mettle)" = 'import "plain.gen";' ]
check "plain (no html, imports b) is generated: plain.gen.mettle:1 imports b.gen" [ "$(sed -n 1p $E/cycle/plain.gen.mettle)" = 'import "b.gen";' ]
check "b.gen.mettle imports a.gen and keeps std/io" [ "$(sed -n 1,2p $E/cycle/b.gen.mettle | tr '\n' ' ')" = 'import "a.gen"; import "std/io"; ' ]
msg=$("$RZPP" $E/unexported/app.mettle 2>&1)
want="$E/unexported/lamp.mettle:2: struct Lamp is in an imported file, so the app cannot call what rzpp generates for it — write \`export struct Lamp\`"
check "unexported struct in an imported file -> [$msg]" [ "$msg" = "$want" ]

echo
if [ $FAIL -eq 0 ]; then echo "RZPP OK ($PASS checks)"; exit 0; fi
echo "RZPP FAILED ($FAIL)"; exit 1
