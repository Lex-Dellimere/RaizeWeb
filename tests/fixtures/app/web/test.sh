#!/usr/bin/env bash
# Guards, cookies, forms, peer address, static files, middleware order, a timer and
# RzConn through rz_run (DECISIONS.md A9-A12).
#   ./tests/fixtures/app/web/test.sh [binary] [port] [rzpp]
# Run from the repository root.
set -u
BIN=${1:-build/web}
PORT=${2:-8079}
[ -n "$PORT" ] || PORT=8079
LOG=$(mktemp)
HDR=$(mktemp)
PID=""
PASS=0
FAIL=0
B=http://127.0.0.1:$PORT

stop() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; fi
  PID=""
}
cleanup() { stop; rm -f "$LOG" "$HDR"; }
trap cleanup EXIT

ok()  { echo "PASS  $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL  $1: $2"; FAIL=$((FAIL + 1)); }
# body <label> <expected-body> <curl args...>: the body must equal the expectation.
body() {
  local label=$1 want=$2; shift 2
  local got; got=$(curl -s --max-time 3 "$@")
  if [ "$got" = "$want" ]; then ok "$label -> $got"; else bad "$label" "want [$want], got [$got]"; fi
}
# head <label> <line-regex> <curl args...>: some response header line matches.
head_has() {
  local label=$1 re=$2; shift 2
  curl -s -o /dev/null -D "$HDR" --max-time 3 "$@"
  if tr -d '\r' < "$HDR" | grep -Eq "$re"; then ok "$label"; else bad "$label" "no header ~$re in: $(tr -d '\r' < "$HDR" | tr '\n' '|')"; fi
}
start() {   # env assignments may precede: start VAR=x ...
  env "$@" "$BIN" --port "$PORT" >"$LOG" 2>&1 &
  PID=$!
  for _ in $(seq 1 50); do grep -q listening "$LOG" && return 0; sleep 0.1; done
  bad "start" "$(cat "$LOG")"; return 1
}

start || exit 1

# ---- guard (A10): /app/* needs the session cookie ------------------------------
CODE=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "$B/app/home")
[ "$CODE" = "303 $B/login" ] && ok "guard: no cookie -> 303 /login" || bad "guard: no cookie" "got $CODE"
head_has "guard runs after global middleware (X-Mw on the redirect)" '^X-Mw: 1$' "$B/app/home"
body "guard: wrong cookie redirects"  "" -b "sid=nope" "$B/app/home"
body "guard: cookie -> handler sees rz_ctx_user" "hello ann" -b "sid=s3cret" "$B/app/home"
body "guard does not cover /apple-ish paths (/login)" "please sign in" "$B/login"
CODE=$(curl -s -o /dev/null -w '%{http_code}' -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
  -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' "$B/app/socket")
[ "$CODE" = "303" ] && ok "guard runs before an upgrade handler under its prefix (303)" || bad "guard on upgrade" "got $CODE"

# ---- cookies (A11) ---------------------------------------------------------------
curl -s -o /dev/null -D "$HDR" -X POST "$B/login"
N=$(tr -d '\r' < "$HDR" | grep -c '^Set-Cookie: ')
[ "$N" = "2" ] && ok "login sets two Set-Cookie lines" || bad "Set-Cookie count" "want 2, got $N: $(tr -d '\r' < "$HDR" | tr '\n' '|')"
tr -d '\r' < "$HDR" | grep -qx 'Set-Cookie: sid=s3cret; Path=/; Max-Age=3600; HttpOnly; SameSite=Lax' \
  && ok "sid cookie attributes exact" || bad "sid cookie" "$(tr -d '\r' < "$HDR" | grep Set-Cookie | tr '\n' '|')"
tr -d '\r' < "$HDR" | grep -qx 'Set-Cookie: theme=dark; Path=/; HttpOnly; SameSite=Lax' \
  && ok "session cookie has no Max-Age" || bad "theme cookie" "$(tr -d '\r' < "$HDR" | grep Set-Cookie | tr '\n' '|')"
JAR=$(mktemp)
curl -s -o /dev/null -c "$JAR" -X POST "$B/login"
body "cookie round trip through a jar" "hello ann" -b "$JAR" "$B/app/home"
curl -s -o /dev/null -b "$JAR" -c "$JAR" -X POST "$B/logout"
body "after logout the guard redirects again" "" -b "$JAR" "$B/app/home"
rm -f "$JAR"
head_has "clear cookie: Max-Age=0" '^Set-Cookie: sid=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax$' -X POST "$B/logout"

# ---- RzConn: what a socket keeps (A9 prerequisite) --------------------------------
body "RzConn copies cookie, peer and user" "theme=dark peer=127.0.0.1 user=ann" -b "sid=s3cret; theme=dark" "$B/app/conn"

# ---- forms (A11) -------------------------------------------------------------------
body "form: + and %XX decoded" "name=[ann lee] note=[a&b=] has_name=true has_missing=false" \
  -X POST -d 'name=ann+lee&note=a%26b%3D' "$B/form"
body "form: JSON body is not a form" "name=[] note=[] has_name=false has_missing=false" \
  -X POST -H 'Content-Type: application/json' -d 'name=x' "$B/form"

# ---- peer (A12) --------------------------------------------------------------------
body "rz_ctx_peer is the socket peer" "127.0.0.1" "$B/peer"
body "X-Forwarded-For ignored without trusted_proxy" "127.0.0.1" -H 'X-Forwarded-For: 9.9.9.9' "$B/peer"

# ---- static, response headers, CORS --------------------------------------------------
body "rz_static serves a file" "hello static" "$B/static/hello.txt"
CODE=$(curl -s --path-as-is -o /dev/null -w "%{http_code}" "$B/static/../app.mettle")
[ "$CODE" = "404" ] || [ "$CODE" = "400" ] && ok "static: no way out of the directory ($CODE)" || bad "static traversal" "got $CODE"
head_has "rz_static sends an ETag" '^ETag: "' "$B/static/hello.txt"
head_has "rz_use_headers on every response" '^X-Content-Type-Options: nosniff$' "$B/peer"
head_has "rz_use_cors answers an Origin" '^Access-Control-Allow-Origin: \*$' -H 'Origin: https://x.test' "$B/peer"

# ---- timer (rz_every 50 ms) -----------------------------------------------------------
T1=$(curl -s "$B/ticks"); sleep 0.5; T2=$(curl -s "$B/ticks")
if [ "$T1" -ge 1 ] 2>/dev/null && [ "$T2" -ge $((T1 + 4)) ] 2>/dev/null; then ok "timer ticks ($T1 -> $T2 in 0.5 s)"; else bad "timer" "$T1 -> $T2"; fi

# ---- trusted proxy: XFF honoured only from it ------------------------------------------
stop
start RAIZE_TRUSTED_PROXY=127.0.0.1 || exit 1
body "XFF honoured from the trusted proxy" "9.9.9.9" -H 'X-Forwarded-For: 9.9.9.9' "$B/peer"
body "XFF: rightmost entry that is not the proxy" "1.1.1.1" -H 'X-Forwarded-For: 5.5.5.5, 1.1.1.1, 127.0.0.1' "$B/peer"
body "XFF: garbage falls back to the socket peer" "127.0.0.1" -H 'X-Forwarded-For: not-an-ip' "$B/peer"
body "no XFF: the socket peer" "127.0.0.1" "$B/peer"
stop

echo
if [ "$FAIL" -eq 0 ]; then echo "WEB OK ($PASS checks)"; exit 0; fi
echo "WEB FAILED ($FAIL of $((PASS + FAIL)))"; exit 1
