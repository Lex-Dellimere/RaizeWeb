#!/usr/bin/env bash
# Fixture apps: runs tests/fixtures/app/<name>/test.sh against <bindir>/<name> for
# every fixture app. Each test.sh takes [binary] [port] [rzpp] and picks its own
# default port (8070..8097).
#   ./tests/integration/apps.sh [bindir]      # default build
set -u
BINDIR=${1:-build}
FAIL=0
N=0
for t in tests/fixtures/app/*/test.sh; do
  name=$(basename "$(dirname "$t")")
  N=$((N + 1))
  echo "== app $name ($BINDIR/$name)"
  if ! "$t" "$BINDIR/$name" "" build/rzpp; then FAIL=$((FAIL + 1)); fi
done
echo
if [ $FAIL -eq 0 ]; then echo "APPS OK ($N apps)"; exit 0; fi
echo "APPS FAILED ($FAIL of $N)"; exit 1
