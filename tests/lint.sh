#!/usr/bin/env bash
# raize layout lint: one responsibility per file.
#   ./tests/lint.sh            # check
# Rules:
#   1. A framework source file carries at most 400 lines of product code
#      (@test blocks are counted separately): one responsibility per file.
#   2. A module that keeps its @test blocks inline must stay under 700 lines
#      total; past that the tests move to a sibling <name>_test.mettle.
#   3. Every exported name carries rz_ / Rz / RZ_.
set -u
LIMIT=${LIMIT:-400}
FAIL=0

product_lines() {
  # strip @test functions (brace counting) and count the rest
  awk '
    /^@test/ { intest = 1; depth = 0 }
    {
      if (intest) {
        n = gsub(/\{/, "{"); depth += n
        m = gsub(/\}/, "}"); depth -= m
        if (depth <= 0 && $0 ~ /\}/) { intest = 0 }
        next
      }
      print
    }' "$1" | wc -l
}

for f in $(find libs/core libs/realtime libs/template libs/signal libs/resource libs/app libs/session -name '*.mettle' -not -path '*/.mbuild/*' -not -path 'libs/session/ses/*' -not -path 'libs/session/tests/*' -not -name mbuild.mettle | sort); do
  case "$f" in
    *_test.mettle) continue ;;
  esac
  n=$(product_lines "$f")
  # framework/str is the base layer: one module, exempt from the split rule.
  case "$f" in
    libs/core/str/*) printf 'ok    %-46s %4s (base layer, exempt)\n' "$f" "$n"; continue ;;
  esac
  if [ "$n" -gt "$LIMIT" ]; then
    printf 'FAIL  %-46s %4s product lines (limit %s)\n' "$f" "$n" "$LIMIT"
    FAIL=$((FAIL + 1))
  else
    printf 'ok    %-46s %4s\n' "$f" "$n"
  fi

  total=$(wc -l < "$f")
  if [ "$total" -gt 700 ] && grep -q '^@test' "$f"; then
    printf 'FAIL  %-46s %4s lines with inline @test: move the tests to %s_test.mettle\n' \
      "$f" "$total" "${f%.mettle}"
    FAIL=$((FAIL + 1))
  fi

  bad=$(grep -E '^export (fn|struct|var|const) ' "$f" | grep -vE '^export (fn|struct|var|const) (rz_|Rz|RZ_)' || true)
  if [ -n "$bad" ]; then
    printf 'FAIL  %-46s exports without rz_/Rz prefix:\n%s\n' "$f" "$bad"
    FAIL=$((FAIL + 1))
  fi
done

echo
if [ "$FAIL" -eq 0 ]; then echo "LINT OK"; exit 0; fi
echo "LINT FAILED ($FAIL)"
exit 1
